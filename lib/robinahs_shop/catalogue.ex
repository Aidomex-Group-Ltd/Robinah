defmodule RobinahsShop.Catalogue do
  @moduledoc """
  Public catalogue rows transcribed from the handwritten stock note.

  Every row keeps the wording of the note so the list can be matched back to
  the document. Listed quantities and amounts are deliberately absent: they
  are neither verified stock nor unit prices, so products are seeded with a
  price of zero and the storefront asks the shop to confirm each price.

  Each row carries one freely licensed (CC0) photograph stored under
  `priv/static/resources`. Photos are never shared between rows; a row whose
  photo is missing simply renders without one instead of repeating another
  item's picture. Sources are recorded in `reference/item-image-sources.json`.
  """

  @items [
    {1, "Cup with numbers", "Home & Kitchen", "piece", "item-01-cup-with-numbers.jpg"},
    {2, "Toilet paper", "Household Plastics & Storage", "roll", "item-02-toilet-paper.jpg"},
    {3, "Colgate Herbal (M)", "Household Plastics & Storage", "tube",
     "item-03-colgate-herbal-toothpaste.jpg"},
    {4, "Nomi buckets", "Household Plastics & Storage", "bucket", "item-04-nomi-buckets.jpg"},
    {5, "Dry cell", "Household Plastics & Storage", "pair", "item-05-dry-cell-batteries.jpg"},
    {6, "Torch", "Household Plastics & Storage", "piece", "item-06-torch.jpg"},
    {7, "Lato milk sachets", "Home & Kitchen", "sachet", "item-07-lato-milk-sachets.jpg"},
    {8, "Ruler", "School Essentials", "piece", "item-08-ruler.jpg"},
    {9, "Black book (1½ Quire)", "School Essentials", "book", "item-09-black-book-quire.jpg"},
    {10, "Mattress Rose Foam (4*6) tape edge", "Bedding & Comfort", "piece",
     "item-10-mattress-rose-foam.jpg"},
    {11, "Butto (1 litre)", "Household Plastics & Storage", "litre",
     "item-11-butto-one-litre.jpg"},
    {12, "Bay… (lb; item name unclear)", "Home & Kitchen", "piece", "item-12-bay-item.jpg"},
    {13, "Bed sheets plain White (Sunbelt)", "Bedding & Comfort", "piece",
     "item-13-bed-sheets-white.jpg"},
    {14, "Mattress ecofoam 4 inch", "Bedding & Comfort", "piece", "item-14-mattress-ecofoam.jpg"},
    {15, "Baby patra", "Bedding & Comfort", "piece", "item-15-baby-patra.jpg"},
    {16, "Rice (half kg)", "Home & Kitchen", "pack", "item-16-rice-half-kg.jpg"},
    {17, "Baby knicker", "Bedding & Comfort", "piece", "item-17-baby-knicker.jpg"},
    {18, "Butto (half litre)", "Household Plastics & Storage", "litre",
     "item-18-butto-half-litre.jpg"},
    {19, "Hand ker chief", "Bedding & Comfort", "piece", "item-19-handkerchief.jpg"},
    {20, "Steel bottle (Medium)", "Bags & Travel", "bottle", "item-20-steel-bottle-medium.jpg"},
    {21, "Relax bottle", "Bags & Travel", "bottle", "item-21-relax-bottle.jpg"},
    {22, "Vest (b)", "Bedding & Comfort", "piece", "item-22-vest.jpg"},
    {23, "Half pot (big)", "Home & Kitchen", "piece", "item-23-half-pot-big.jpg"},
    {24, "Set mathematical", "School Essentials", "set", "item-24-set-mathematical.jpg"},
    {25, "Blue soap", "Household Plastics & Storage", "bar", "item-25-blue-soap.jpg"},
    {26, "Ruler", "School Essentials", "piece", "item-26-ruler-second.jpg"},
    {27, "Shoe polish (Kangaroo)", "Household Plastics & Storage", "tin",
     "item-27-shoe-polish-kangaroo.jpg"},
    {28, "Shoe brush", "Household Plastics & Storage", "piece", "item-28-shoe-brush.jpg"},
    {29, "Rubber", "School Essentials", "piece", "item-29-rubber-eraser.jpg"},
    {30, "Geisha (small)", "Home & Kitchen", "bottle", "item-30-geisha-small.jpg"},
    {31, "Go-back stocks", "Bags & Travel", "piece", "item-31-go-back-stocks.jpg"},
    {32, "Breakable bowl / plate", "Home & Kitchen", "piece", "item-32-breakable-bowl-plate.jpg"},
    {33, "Angel cup (s)", "Home & Kitchen", "piece", "item-33-angel-cup.jpg"},
    {34, "Sponge", "Household Plastics & Storage", "piece", "item-34-sponge.jpg"},
    {35, "Colgate charcoal (b)", "Household Plastics & Storage", "tube",
     "item-35-colgate-charcoal-toothpaste.jpg"},
    {36, "Vaseline (b)", "Household Plastics & Storage", "jar", "item-36-vaseline-jar.jpg"}
  ]

  @doc "All catalogue rows as `{number, name, category, unit, image_file}` tuples."
  def items, do: @items

  @doc "Number of rows transcribed from the handwritten note."
  def count, do: length(@items)

  @doc "Stocking code for a note row, e.g. `sku(8)` is `\"RSH-008\"`."
  def sku(number) when is_integer(number),
    do: "RSH-" <> String.pad_leading(Integer.to_string(number), 3, "0")
end
