export interface ApiResponseEnvelope<TData> {
  success: boolean;
  data?: TData;
  message?: string | null;
  errors?: string[] | null;
}

export interface AvailableTenant {
  tenantId: number;
  tenantCode: string;
  tenantName: string;
}

export interface RuntimeConfiguration {
  activeTenantCode: string;
  configuredActiveTenantCode: string;
  tenantHeaderName: string;
  availableTenants: AvailableTenant[];
}

export interface OrderSummary {
  orderId: number;
  orderDate: string;
  customerId: number;
  totalPrice: number;
  status: string;
  isFulfilled: boolean;
}

export interface ProductSummary {
  productId: number;
  name: string;
  description?: string | null;
  price: number;
}

export interface OrderProductSummary {
  sysId: number;
  orderId: number;
  productId: number;
  quantity: number;
  price: number;
  productDto?: ProductSummary | null;
}

export interface OrderDetail extends OrderSummary {
  orderProductDtos?: OrderProductSummary[] | null;
}

export interface CreateOrderRequest {
  customerId: number;
  productIds: number[];
}

export interface ProcessPaymentRequest {
  name: string;
  email: string;
  deviceSessionId: string;
  cardNumber: string;
  expirationYear: string;
  expirationMonth: string;
  cvv2: string;
  customerOrderId: string;
  clientCallbackOrigin?: string | null;
}

export interface PaymentStatusLookupRequest {
  attemptOrderId?: string | null;
  callbackStatus?: string | null;
  errorMessage?: string | null;
  callbackParameters?: Record<string, string> | null;
}

export interface PaymentResult {
  id: string;
  customerOrderId: string;
  customerId: string;
  amount: number;
  currency: string;
  status: string;
  createdAt: string;
  transactionId?: string | null;
  errorMessage?: string | null;
  threeDSecureUrl?: string | null;
  isThreeDSecureEnabled: boolean;
  threeDSecureStage?: string | null;
}

export interface PaymentStatusDetails {
  paymentId: string;
  customerOrderId: string;
  status: string;
  statusCategory: string;
  statusMessage: string;
  isSuccess: boolean;
  isPending: boolean;
  isFailure: boolean;
  isFinal: boolean;
  callbackRecorded: boolean;
  remoteStatusConfirmed: boolean;
  statusSource: string;
  errorMessage?: string | null;
  transactionReferenceId?: string | null;
  transactionDate?: string | null;
  threeDSecureUrl?: string | null;
  isThreeDSecureEnabled: boolean;
  threeDSecureStage?: string | null;
}

export interface CustomerSummary {
  customerId: number;
  name: string;
  email: string;
  orderDtos: OrderSummary[];
}