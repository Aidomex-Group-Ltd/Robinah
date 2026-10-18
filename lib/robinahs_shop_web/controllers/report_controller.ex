defmodule RobinahsShopWeb.ReportController do
  use RobinahsShopWeb, :controller

  def export(conn, params) do
    case RobinahsShop.Shop.export_csv(conn.assigns.current_user, params) do
      {:ok, csv} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> send_download({:binary, csv},
          filename: "robinahs-sales-report.csv",
          content_type: "text/csv; charset=utf-8"
        )

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> text("Owner or manager access required.")

      {:error, _} ->
        conn |> put_status(:bad_request) |> text("Invalid date range.")
    end
  end
end

defmodule RobinahsShopWeb.HealthController do
  use RobinahsShopWeb, :controller

  def index(conn, _) do
    case Ecto.Adapters.SQL.query(RobinahsShop.Repo, "SELECT 1", []) do
      {:ok, _} -> json(conn, %{status: "ok"})
      _ -> conn |> put_status(:service_unavailable) |> json(%{status: "unavailable"})
    end
  end
end
