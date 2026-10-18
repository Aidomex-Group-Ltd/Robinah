defmodule RobinahsShopWeb.InventoryController do
  use RobinahsShopWeb, :controller

  def export(conn, _params) do
    case RobinahsShop.StockList.export_csv(conn.assigns.current_user) do
      {:ok, csv} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> send_download({:binary, csv},
          filename: "robinahs-inventory-review.csv",
          content_type: "text/csv; charset=utf-8"
        )

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> text("Receiving access required.")
    end
  end
end
