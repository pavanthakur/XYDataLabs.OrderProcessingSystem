import type { Page } from "playwright";

// A same-origin popup with its opener inherits a browser-managed copy of
// sessionStorage. A context.newPage() tab starts with an empty MSAL cache.
export async function openSameSessionTab(page: Page, url: string): Promise<Page> {
  if (new URL(url).origin !== new URL(page.url()).origin) {
    throw new Error("Session tab must use the authenticated application origin.");
  }
  const [tab] = await Promise.all([
    page.waitForEvent("popup", { timeout: 15000 }),
    page.evaluate(target => { window.open(target, "_blank"); }, url)
  ]);
  return tab;
}
