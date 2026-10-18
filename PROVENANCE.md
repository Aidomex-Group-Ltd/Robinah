# Source provenance

Reference app: https://robinah-s-shop-qlr4ne.v2.appdeploy.ai/

Observed app version: `1792274701942`. Public browser assets retrieved on 18 October 2026.

The AppDeploy source connector returned “App not found or unauthorized.” A public deployment does not reveal the private server code or database. This deliverable therefore contains a newly written Elixir/Phoenix/LiveView application and the observed public client artifacts. It is not a verbatim export of an existing Elixir project.

The original public JavaScript bundle and CSS are retained under `reference/` for audit. The recovered branding, shop photograph and six referenced Unsplash category images are copied to `priv/static/resources/`; their source URLs and SHA-256 hashes are in `reference/image-sources.json`. These illustrative images do not establish saleable inventory. Original asset rights and third-party dependency licences remain with their respective owners.

The original AppDeploy login/backend are replaced by local Phoenix staff authentication and an Ecto PostgreSQL database. Staff access records, historical sales, receivings and private inventory must be migrated separately from an authorised export. No original passwords or secrets have been copied. The reconstructed application does not call AppDeploy at runtime. Google Maps, optional Google Fonts and WhatsApp remain external visitor services.

The unauthenticated public catalogue endpoint returned `{"items":[],"source":"server"}` during inspection. The six fallback category listings from the browser bundle are therefore used as the initial illustrative catalogue.
