namespace XYDataLabs.OpenPayAdapter
{
    public class OpenPayException : Exception
    {
        public int ErrorCode { get; }
        public string Category { get; }
        public int HttpCode { get; }
        public string RequestId { get; }

        public OpenPayException(
            string message,
            int errorCode,
            string category,
            int httpCode,
            string requestId
        ) : base(message)
        {
            ErrorCode = errorCode;
            Category = category;
            HttpCode = httpCode;
            RequestId = requestId;
        }
    }

    public class OpenPayError
    {
        public string Description { get; set; } = string.Empty;
        public int ErrorCode { get; set; }
        public string Category { get; set; } = string.Empty;
        public int HttpCode { get; set; }
        public string RequestId { get; set; } = string.Empty;
    }
}
