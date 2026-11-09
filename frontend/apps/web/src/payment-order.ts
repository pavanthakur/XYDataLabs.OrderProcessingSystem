import type { OrderSummary } from "@xydatalabs/orderprocessing-api-sdk";

export function isEligiblePaymentOrder(order: OrderSummary): boolean {
  return order.status === "Created" && Number.isInteger(order.orderId) && order.orderId > 0
    && Number.isFinite(order.totalPrice) && order.totalPrice > 0 && Boolean(order.currencyCode?.trim())
    && Boolean(order.orderReferenceId && /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(order.orderReferenceId)
      && order.orderReferenceId !== "00000000-0000-0000-0000-000000000000");
}
