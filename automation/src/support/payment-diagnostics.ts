export function safePaymentDiagnostic(message:string):string {
  return message.replace(/https?:\/\/[^\s"'<>]+/g, value=>{
    try {const url=new URL(value); return `${url.origin}${url.pathname}`;} catch{return "[URL REDACTED]";}
  }).replace(/\b(?:\d[ -]?){13,19}\b/g,"[CARD OR TOKEN REDACTED]");
}
