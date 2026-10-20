import { chromium } from "playwright";

const BASE_URL = process.env.E2E_BASE_URL || "http://127.0.0.1:4300";
const EMAIL = process.env.E2E_ADMIN_EMAIL || "abenitwerobinah@gmail.com";
const PASSWORD =
  process.env.E2E_ADMIN_PASSWORD ||
  "33d6751617f4e24dac8cf57fd8761ed18566864078f878493b4795d9c57336fc";

let failures = 0;
const step = (name, ok, detail = "") => {
  const status = ok ? "PASS" : "FAIL";
  if (!ok) failures += 1;
  console.log(`${status}  ${name}${detail ? ` — ${detail}` : ""}`);
};

const browser = await chromium.launch();
const page = await browser.newPage();

// The stylesheet imports Google Fonts; in an offline CI box that request hangs
// and page-load events never fire, so only the app origin is allowed through.
const appHost = new URL(BASE_URL).host;
await page.route("**/*", (route) => {
  const { host } = new URL(route.request().url());
  if (host === appHost || host === "") {
    return route.continue();
  }
  return route.abort();
});

try {
  // 1. Anonymous staff URL bounces to the sign-in form.
  await page.goto(`${BASE_URL}/staff/pos`, { waitUntil: "domcontentloaded" });
  await page.waitForURL("**/staff/sign-in", { timeout: 15_000 });
  step("anonymous /staff/pos redirects to sign-in", true);

  const heading = await page.locator(".staff-shell h1").first().innerText();
  step("sign-in page renders", heading.trim() === "Staff sign-in", `h1=${heading.trim()}`);

  // 2. Wrong password is rejected with a flash error and no session.
  await page.fill('input[name="login[email]"]', EMAIL);
  await page.fill('input[name="login[password]"]', "definitely-not-the-password");
  await page.click('button[type="submit"]');
  await page.waitForURL("**/staff/sign-in", { timeout: 15_000 });
  const flash = await page.locator('[role="alert"]').first().innerText();
  step(
    "wrong password rejected",
    flash.includes("Email or password was not recognised."),
    flash.trim()
  );

  // 3. Real admin credentials sign in and open the point of sale.
  await page.fill('input[name="login[email]"]', EMAIL);
  await page.fill('input[name="login[password]"]', PASSWORD);
  await page.click('button[type="submit"]');
  await page.waitForURL("**/staff/pos", { timeout: 30_000 });
  step("admin sign-in lands on /staff/pos", page.url() === `${BASE_URL}/staff/pos`, page.url());

  const posHeading = await page.locator(".staff-shell h1").first().innerText();
  step("point of sale renders", posHeading.trim() === "Point of sale", `h1=${posHeading.trim()}`);

  const welcome = await page.locator(".staff-welcome").first().innerText();
  step(
    "signed-in admin is shown with role",
    welcome.includes("Signed in") && welcome.includes("Shop owner") && welcome.includes("owner"),
    welcome.replace(/\s+/g, " ").trim()
  );

  await page.locator('nav.staff-tabs a', { hasText: "Products" }).first().click();
  await page.waitForURL("**/staff/products", { timeout: 15_000 });
  const productsHeading = await page.locator(".staff-shell h1").first().innerText();
  step(
    "owner can open staff-only products page",
    productsHeading.includes("Products & prices") || productsHeading.includes("Products &"),
    `h1=${productsHeading.trim()}`
  );

  // 4. Sign out ends the session and returns to the public shop.
  await page.locator(".staff-welcome button", { hasText: "Sign out" }).first().click();
  await page.waitForURL((url) => url.pathname === "/", { timeout: 15_000 });
  step("sign out returns to the public shop", true, page.url());
} catch (error) {
  step("e2e run completed without errors", false, error.message);
} finally {
  await browser.close();
}

if (failures > 0) {
  console.error(`\n${failures} admin sign-in e2e check(s) failed.`);
  process.exit(1);
}

console.log("\nAll admin sign-in e2e checks passed.");
