defmodule RobinahsShopWeb.Cart do
  @moduledoc """
  Shared cart/basket helpers used across storefront and POS.
  Keeps quantities as strings (product ids) like existing code.
  """

  def new, do: %{}

  def add(cart, id) when is_binary(id) do
    Map.update(cart, id, 1, fn q -> min(q + 1, 100_000) end)
  end

  def add(cart, id), do: add(cart, to_string(id))

  def minus(cart, id) when is_binary(id) do
    cart
    |> Map.update(id, 0, &max(&1 - 1, 0))
    |> Map.reject(fn {_k, q} -> q == 0 end)
  end

  def minus(cart, id), do: minus(cart, to_string(id))

  def remove(cart, id) when is_binary(id), do: Map.delete(cart, id)
  def remove(cart, id), do: remove(cart, to_string(id))

  def count(cart), do: cart |> Map.values() |> Enum.sum()

  def items(products, cart) when is_list(products) do
    Enum.filter(products, fn p -> Map.get(cart, to_string(p.id), 0) > 0 end)
  end

  def total(products, cart) do
    Enum.reduce(items(products, cart), 0, fn p, sum ->
      sum + p.price * Map.get(cart, to_string(p.id), 0)
    end)
  end

  def row_total(p, cart) do
    p.price * Map.get(cart, to_string(p.id), 0)
  end

  def has_unconfirmed_prices?(products, cart) do
    Enum.any?(items(products, cart), fn p -> p.price <= 0 end)
  end

  def to_sale_items(cart) do
    Enum.map(cart, fn {id, qty} -> %{"product_id" => id, "quantity" => qty} end)
  end
end
