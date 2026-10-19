import {Socket} from "./phoenix.mjs"
import {LiveSocket} from "./phoenix_live_view.mjs"
const csrfToken = document.querySelector("meta[name='csrf-token']").content
const liveSocket = new LiveSocket("/live", Socket, {params: {_csrf_token: csrfToken}})
liveSocket.connect()
window.addEventListener("phx:print", () => window.print())
window.addEventListener("phx:scroll-catalogue", () => document.getElementById("catalogue")?.scrollIntoView({behavior:"smooth"}))
window.addEventListener("phx:scroll-basket", () => document.getElementById("sale-basket")?.scrollIntoView({behavior:"smooth",block:"nearest"}))
window.addEventListener("phx:focus-receipt", () => document.getElementById("receipt")?.scrollIntoView({behavior:"smooth",block:"start"}))
window.addEventListener("phx:page-loading-start", () => document.documentElement.classList.add("loading"))
window.addEventListener("phx:page-loading-stop", () => document.documentElement.classList.remove("loading"))
