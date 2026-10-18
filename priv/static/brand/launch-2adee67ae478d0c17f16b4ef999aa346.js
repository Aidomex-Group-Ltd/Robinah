// A short brand launch on the first full page load in each tab.
// Browsing stays usable if storage, JavaScript or the main bundle is unavailable.
// The overlay is hidden by a <noscript> rule when JavaScript is disabled, and it
// also dismisses on the first interaction so it can never trap the user.
(() => {
  const launch = document.getElementById("brand-launch");
  if (!launch) return;
  const root = document.documentElement;
  let done = false;
  const finish = () => {
    if (done) return;
    done = true;
    root.classList.remove("brand-starting");
    launch.style.transition = "opacity 300ms ease";
    launch.style.opacity = "0";
    window.setTimeout(() => {
      launch.style.display = "none";
    }, 300);
  };
  let show = true;
  try {
    show = sessionStorage.getItem("robinahs:brand-launched") !== "1";
    sessionStorage.setItem("robinahs:brand-launched", "1");
  } catch (_) {
    /* Storage can be unavailable in private browsing. */
  }
  if (!show) {
    launch.style.display = "none";
    root.classList.remove("brand-starting");
    return;
  }
  root.classList.add("brand-starting");
  window.addEventListener("load", finish, {once: true});
  window.addEventListener("pageshow", finish, {once: true});
  ["pointerdown", "keydown", "touchstart"].forEach((event) => {
    window.addEventListener(event, finish, {once: true, passive: true});
  });
  window.setTimeout(finish, 2500);
})();
