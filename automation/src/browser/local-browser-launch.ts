/** Launch is injected so missing-browser and headed-launch behavior need no identity/provider access. */
export async function launchLocalBrowser<T>(launch: (options: { headless: boolean; args: string[] }) => Promise<T>, headless: boolean, operator: boolean): Promise<T> {
  try {
    return await launch({ headless, args: operator ? ["--start-maximized"] : [] });
  } catch {
    throw new Error("BROWSER_LAUNCH_FAILED: run from your signed-in desktop terminal; verify Playwright Chromium is installed. No payment was submitted by this journey.");
  }
}
