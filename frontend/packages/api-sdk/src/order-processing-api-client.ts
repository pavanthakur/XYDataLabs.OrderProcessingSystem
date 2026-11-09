import type {
  ApiResponseEnvelope,
  CreateOrderRequest,
  CustomerSummary,
  OrderDetail,
  PaymentConfiguration,
  PaymentRuntime,
  PaymentStatusDetails,
  PaymentStatusLookupRequest,
  PaymentResult,
  ProcessPaymentRequest,
  ProductSummary,
  RuntimeConfiguration
} from "./contracts";

export interface OrderProcessingApiClientOptions {
  baseUrl?: string;
  getTenantCode?: () => string | null;
  getTenantHeaderName?: () => string | null;
  getAccessToken?: () => string | null;
}

const defaultTenantHeaderName = "X-Tenant-Code";

export class ApiRequestError extends Error {
  readonly statusCode: number;

  constructor(message: string, statusCode: number) {
    super(message);
    this.name = "ApiRequestError";
    this.statusCode = statusCode;
  }
}

export class OrderProcessingApiClient {
  private requestController = new AbortController();

  cancelPendingRequests(): void {
    this.requestController.abort();
    this.requestController = new AbortController();
  }
  private readonly baseUrl: string;
  private readonly getTenantCode: () => string | null;
  private readonly getTenantHeaderName: () => string | null;
  private readonly getAccessToken: () => string | null;

  constructor(options: OrderProcessingApiClientOptions = {}) {
    this.baseUrl = options.baseUrl?.replace(/\/$/, "") ?? "";
    this.getTenantCode = options.getTenantCode ?? (() => null);
    this.getTenantHeaderName = options.getTenantHeaderName ?? (() => null);
    this.getAccessToken = options.getAccessToken ?? (() => null);
  }

  async getRuntimeConfiguration(requestedTenantCode?: string): Promise<RuntimeConfiguration> {
    return this.requestJson<RuntimeConfiguration>("/api/v1/Info/runtime-configuration", {
      headers: this.buildHeaders(requestedTenantCode)
    });
  }

  async getPaymentConfiguration(requestedTenantCode?: string): Promise<PaymentConfiguration> {
    const configuration = await this.requestJson<PaymentConfiguration>("/api/v1/Info/payment-configuration", {
      headers: this.buildHeaders(requestedTenantCode)
    });
    const runtime = await this.getPaymentRuntime(requestedTenantCode);
    if (!["sandbox","live","deterministic"].includes(runtime.adapterMode)) throw new Error("Payment runtime adapter mode is missing or unrecognized.");
    if (runtime.providerType !== configuration.activeProviderType || runtime.collectionMode !== configuration.collectionMode
      || runtime.isProduction !== configuration.isProduction || runtime.configuredThreeDs !== configuration.isThreeDSecure) {
      throw new Error("Orders and Payments runtime configuration disagree. Reload after restoring tenant settings.");
    }
    if (runtime.providerType.toLowerCase() === "razorpay"
      && (!Array.isArray(runtime.supportedCurrencies) || runtime.supportedCurrencies.length === 0
        || runtime.supportedCurrencies.some(currency => typeof currency !== "string" || !/^[A-Z]{3}$/.test(currency)))) {
      throw new Error("Razorpay runtime currency capabilities are unavailable. Reload after updating the Payments service.");
    }
    return { ...configuration, adapterMode: runtime.adapterMode, supportedCurrencies: runtime.supportedCurrencies };
  }

  async getPaymentRuntime(requestedTenantCode?: string): Promise<PaymentRuntime> {
    return this.requestEnvelope<PaymentRuntime>("/api/v1/Payments/runtime", { headers: this.buildHeaders(requestedTenantCode) });
  }

  async getAllCustomers(): Promise<CustomerSummary[]> {
    return this.requestEnvelope<CustomerSummary[]>(
      "/api/v1/Customer/GetAllCustomers",
      {
        headers: this.buildHeaders()
      }
    );
  }

  async searchCustomersByName(name: string, pageNumber = 1, pageSize = 10): Promise<CustomerSummary[]> {
    const query = new URLSearchParams({
      name,
      pageNumber: pageNumber.toString(),
      pageSize: pageSize.toString()
    });

    return this.requestEnvelope<CustomerSummary[]>(`/api/v1/Customer/GetAllCustomersByName?${query.toString()}`, {
      headers: this.buildHeaders()
    });
  }

  async getCustomerById(customerId: number): Promise<CustomerSummary> {
    return this.requestEnvelope<CustomerSummary>(`/api/v1/Customer/${customerId}`, {
      headers: this.buildHeaders()
    });
  }

  async getAllProducts(): Promise<ProductSummary[]> {
    return this.requestEnvelope<ProductSummary[]>("/api/v1/Product/GetAllProducts", {
      headers: this.buildHeaders()
    });
  }

  async getOrderById(orderId: number): Promise<OrderDetail> {
    return this.requestEnvelope<OrderDetail>(`/api/v1/Order/${orderId}`, {
      headers: this.buildHeaders()
    });
  }

  async createOrder(request: CreateOrderRequest): Promise<OrderDetail> {
    return this.requestEnvelope<OrderDetail>("/api/v1/Order", {
      method: "POST",
      headers: {
        ...this.buildHeaders(),
        "Content-Type": "application/json"
      },
      body: JSON.stringify(request)
    });
  }

  async processPayment(request: ProcessPaymentRequest): Promise<PaymentResult> {
    return this.requestEnvelope<PaymentResult>("/api/v1/Payments/ProcessPayment", {
      method: "POST",
      headers: {
        ...this.buildHeaders(),
        "Content-Type": "application/json"
      },
      body: JSON.stringify(request)
    });
  }

  async confirmPaymentStatus(
    paymentId: string,
    request: PaymentStatusLookupRequest,
    requestedTenantCode?: string
  ): Promise<PaymentStatusDetails> {
    return this.requestEnvelope<PaymentStatusDetails>(`/api/v1/Payments/${encodeURIComponent(paymentId)}/confirm-status`, {
      method: "POST",
      headers: {
        ...this.buildHeaders(requestedTenantCode),
        "Content-Type": "application/json"
      },
      body: JSON.stringify(request)
    });
  }

  private async requestEnvelope<TData>(path: string, init?: RequestInit): Promise<TData> {
    const response = await this.requestJson<ApiResponseEnvelope<TData>>(path, init);

    if (!response.success) {
      throw new ApiRequestError(this.getEnvelopeErrorMessage(response), 400);
    }

    if (response.data === undefined) {
      throw new ApiRequestError("The API response did not include the expected payload.", 500);
    }

    return response.data;
  }

  private async requestJson<TResponse>(path: string, init?: RequestInit): Promise<TResponse> {
    const response = await fetch(`${this.baseUrl}${path}`, {
      signal: this.requestController.signal,
      credentials: "include",
      ...init,
      headers: {
        Accept: "application/json",
        ...(this.getAccessToken() ? { Authorization: `Bearer ${this.getAccessToken()}` } : {}),
        ...(init?.headers ?? {})
      }
    });

    if (!response.ok) {
      if (response.status === 401 && typeof window !== "undefined") window.dispatchEvent(new Event("orderprocessing.session-expired"));
      throw new ApiRequestError(await this.getRequestErrorMessage(response), response.status);
    }

    return (await response.json()) as TResponse;
  }

  private async getRequestErrorMessage(response: Response): Promise<string> {
    const contentType = response.headers.get("content-type") ?? "";
    // Consume the stream once: JSON errors may be empty, malformed, or use
    // an unrecognized shape. Falling back must not read the body again.
    const errorText = await response.text();

    if (contentType.includes("application/json") || contentType.includes("+json")) {
      let payload: unknown = null;
      try {
        payload = JSON.parse(errorText);
      } catch {
        // Preserve non-JSON response text below.
      }
      if (payload && typeof payload === "object") {
        const errorPayload = payload as {
          detail?: unknown;
          title?: unknown;
          message?: unknown;
          errors?: unknown;
          error?: unknown;
        };

        if (Array.isArray(errorPayload.errors) && errorPayload.errors.length > 0) {
          const messages = errorPayload.errors.filter((value): value is string => typeof value === "string" && value.length > 0);
          if (messages.length > 0) return messages.join(" ");
        }

        if (typeof errorPayload.detail === "string" && errorPayload.detail.length > 0) {
          return errorPayload.detail;
        }

        if (typeof errorPayload.message === "string" && errorPayload.message.length > 0) {
          return errorPayload.message;
        }

        if (typeof errorPayload.title === "string" && errorPayload.title.length > 0) {
          return errorPayload.title;
        }
        if (typeof errorPayload.error === "string" && errorPayload.error.length > 0) {
          return errorPayload.error;
        }
      }
    }

    return errorText || `Request failed with status ${response.status}.`;
  }

  private buildHeaders(requestedTenantCode?: string): HeadersInit {
    const tenantCode = requestedTenantCode ?? this.getTenantCode();
    const tenantHeaderName = this.getTenantHeaderName() ?? (tenantCode ? defaultTenantHeaderName : null);

    if (!tenantHeaderName || !tenantCode) {
      return {};
    }

    return {
      [tenantHeaderName]: tenantCode
    };
  }

  private getEnvelopeErrorMessage<TData>(response: ApiResponseEnvelope<TData>): string {
    if (response.errors && response.errors.length > 0) {
      return response.errors.join(" ");
    }

    return response.message ?? "The API request failed.";
  }
}

export function createOrderProcessingApiClient(options?: OrderProcessingApiClientOptions): OrderProcessingApiClient {
  return new OrderProcessingApiClient(options);
}
