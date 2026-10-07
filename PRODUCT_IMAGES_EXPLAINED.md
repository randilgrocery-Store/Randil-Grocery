# Product Images — How They Work and How to Deliver Them

For the developer and the client. No code knowledge needed to follow this.

---

## 1. The Short Version

When you pick a photo for a product, the app:

1. **Copies** the photo into its own folder on the computer
2. **Stores only the file's name** in the database (e.g. `1758231041203045.jpg`)

It does **not** store where the photo originally was. That is the whole trick.

**To give the client their data, copy one folder:**

```
C:\Users\<you>\AppData\Local\RandilGroceryPOS\
```

That folder contains the database **and** the images. Copy the whole folder to the client's computer. Both go together.

---

## 2. Why It Works This Way

### The mistake that causes the bug

Most programs store the *full path* of the image:

```
C:\Users\jerus\AppData\Local\RandilGroceryPOS\product_images\1758231041203045.jpg
                                    ^^^^^^
                                    this part is the problem
```

Two things break that:

**a) `jerus` is your username.** The client's username is different. When you hand them that database, the app looks for a folder called `C:\Users\jerus\...` on their computer, finds nothing, and **every single image disappears**. Not one broken image — all of them.

**b) Downloads and Desktop are not safe.** If you pick a photo from `Downloads\photo.jpg` and later move, rename, or empty that file, the product loses its picture with no warning.

### What this app does instead

The database stores only:

```
1758231041203045.jpg
```

Just the name. When the app needs to show the image, it works out the full path at that moment, using the **current** computer's `%LOCALAPPDATA%`. So on your machine it builds `C:\Users\jerus\...`, and on the client's it builds `C:\Users\client\...` — automatically, with nothing to configure.

The photo itself is copied into the app's folder first, so it cannot be moved or deleted out from under the product.

---

## 3. The Three Cases the App Handles

Your database may contain any of these. All three display correctly.

| What is stored | What happens |
|---|---|
| `1758231041203045.jpg` | **Normal.** Rebuilt into the current computer's folder. |
| `C:\Users\jerus\...\image.jpg` (file is here) | **Old format, same computer.** Used as-is. |
| `C:\Users\old-owner\...\image.jpg` (foreign) | **Delivered from elsewhere.** Takes just the file name and looks in the local folder. |

The third case is the safety net: if you copy the folder to the client but a row still holds the old machine's path, the image is **recovered** rather than staying broken.

---

## 4. Delivering to the Client

### The one rule

**Copy the entire `RandilGroceryPOS` folder. Never just the `.db` file.**

### Steps

**On your machine:**

1. Close the app completely.
2. Open this folder (paste into File Explorer):
   ```
   %LOCALAPPDATA%\RandilGroceryPOS
   ```
   You should see `randil_grocery_pos.db`, a `product_images` folder, and a `backups` folder.

**On the client's machine:**

3. Install and open the app once, so it creates the folder. Then **close** it.
4. Copy **everything** from your `RandilGroceryPOS` over theirs. Say yes to replace.

### Checking it worked

On the client, the app should show all products **with their photos**.

If a photo is missing, that single image file did not arrive. Copy the `product_images` folder again.

### If the client uses a different Windows account

That is fine — it is the point of this design. The app finds images in whatever profile is running it.

---

## 5. One Thing to Know: Existing Images

Photos added **before** this fix are still stored the old way (full path). They **display fine** — the app handles all three cases above.

But if you want the delivered database to be completely clean, re-pick the photo on those products:

**Inventory → find the product → Edit → Select Image → Save**

Each takes about ten seconds. Only worth doing for products with photos; the rest are unaffected.

---

## 6. Adding New Products (the normal flow)

1. **Inventory → Add Product**
2. Fill in name, barcode, category, buying price, selling price
3. **Select Image** → choose the photo
4. Check the preview shows the **whole product**, not a cropped slice
5. **Save**

The photo is copied into the app folder automatically. You never manage the files yourself.

### Two tips

- **Use the barcode printed on the pack.** That exact string is what the scanner must send. One wrong digit and the item cannot be sold by scanning, though it looks fine on screen.
- **Weights:** loose goods (fruit, vegetables, fish, meat) should use **Sold by weight (kg)**. Packaged goods stay **Sold by piece**.

---

## 7. Stock Is a Separate Step

Adding a product does **not** put stock on the shelf. A new product starts at zero, and the counter will say *"is out of stock"* rather than sell it.

**To bring stock in:** use the **GRN (Goods Received Note)** screen. Scan or enter the items and quantities. That is what makes them sellable.

Order of operations for a new item:

```
Add Product  →  quantity 0, not sellable yet
GRN          →  stock arrives, now sellable
scan at POS  →  goes in the cart
```

---

## 8. Categories

Thirteen are already set up:

Beverages · Bakery · Baby Care · Canned & Dry Goods · Dairy & Eggs ·
Fruits & Vegetables · Frozen Foods · Household & Cleaning · Meat, Fish & Poultry ·
Personal Care · Rice, Flour & Grains · Snacks & Confectionery · No Barcode

Common placements:

| Item | Category |
|---|---|
| Full cream milk (carton) | Dairy & Eggs |
| Full cream milk powder (tin) | Dairy & Eggs |
| Milk powder marketed for infants | Baby Care |
| Cutee diapers (any size) | Baby Care |
| Soap, shampoo, toothpaste | Personal Care |
| Washing powder, dishwash | Household & Cleaning |

Add or rename categories in **Inventory**.

---

## 9. Cash Drawer — When It Opens

The drawer opens **after a sale is saved**, never before. This matters: if the save fails the customer is not charged and the drawer does not open.

| Situation | Drawer opens? |
|---|---|
| Cash sale | Yes |
| Card sale, no cash tendered | Only if *Open on card payments* is on in Settings |
| Split (cash + card), any cash taken | Yes |
| Sale failed to save | **No** |
| Manual **Open Drawer** button | Yes, immediately |

**Only once per sale.** The app records that a drawer command was sent, so a retry after a failure can never pop it twice, and a re-render can never re-trigger it.

Settings → Cash Drawer: enable/disable, printer, pin, and how long the drawer stays open.

If it fails, the bill is still saved and the customer is still paid — the app shows a specific "cash drawer did not open" message with a **Retry** button, so staff know to check the RJ11 cable rather than assume the sale failed.

---

## 10. Scanning at the Counter

1. Click the POS screen once (the scanner box takes focus).
2. Scan an item — it is added to the cart automatically.
3. Scan two **different** items back to back — **both** must appear. (This used to silently drop the second one.)
4. Scan the **same** item twice as two separate scans — quantity should read **2**.

If a scan does nothing, the item is either out of stock, or its barcode does not match. The app tells you which.

---

## Quick Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| No photos after delivery | `product_images` folder was not copied | Copy the whole folder |
| One product has no photo | That image file did not arrive | Copy `product_images` again |
| Photo cropped / unreadable | Old build, before the fit fix | Re-select the photo |
| Item scans but is "out of stock" | No GRN yet | Receive stock via GRN |
| "No product matches" | Barcode in database ≠ barcode on pack | Edit product, correct the barcode |
| Item not sellable by scan | Case or character mismatch | Check the barcode character by character |

---

## Files Changed (developer reference)

| File | Purpose |
|---|---|
| `lib/presentation/widgets/product_image.dart` | `ProductImage` (display) and `ProductImageStore` (storage) |
| `lib/presentation/screens/inventory/inventory_screen.dart` | Pick + preview + inventory grid |
| `lib/presentation/screens/pos/pos_screen.dart` | POS grid, preview dialog, cart line |
| `test/product_image_test.dart` | Tests for the rules above |

Key entry points:

- `ProductImageStore.store(pickedPath)` → copies the file, returns the **filename** to save
- `ProductImageStore.resolve(storedValue)` → filename or foreign path → absolute path on this machine, or `null`
- `ProductImage.hasImage(storedValue)` → `true` only if it resolves to a real file