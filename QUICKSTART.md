# Quick Start Guide - Randil Grocery POS

## 5-Minute Setup

### Step 1: Get the Code
```bash
cd c:\Users\jerus\Desktop\Randil Grocery POS
flutter clean
flutter pub get
```

### Step 2: Run the App
```bash
flutter run -d windows
```

### Step 3: Login
- **Username**: `admin` or `cashier`
- **Password**: `admin123` or `cashier123`

### Step 4: Add Your First Product
1. Go to **Inventory** tab
2. Click **Add Product**
3. Fill in details:
   - Name: "Rice (10kg)"
   - Barcode: "123456789"
   - Category: "Groceries"
   - Buying Price: 450
   - Selling Price: 550
   - Quantity: 50

### Step 5: Make Your First Sale
1. Go to **POS** tab
2. Click on the product you added OR scan its barcode
3. Adjust quantity if needed
4. Enter payment amount (e.g., 550)
5. Click **Complete Sale**
6. Print or view receipt

### Step 6: Check Reports
1. Go to **Reports** tab
2. View today's sales in **Daily Report**
3. Check revenue, transactions, and items sold

---

## Key Shortcuts & Tips

### POS Screen Tips
- **Tab**: Move between barcode field and payment field
- **Enter**: Scan/search product or submit
- **+/-**: Adjust quantity quickly
- **Clear**: Reset cart and start over

### Keyboard Shortcuts
- **Ctrl+Shift+P**: Open printer settings (planned)
- **Ctrl+Q**: Quick logout (planned)

### Admin Super Powers
- Access user management
- Modify system settings
- View all reports
- Edit/delete any product

---

## Common First-Time Tasks

### Task 1: Set Up Shop Details
1. Go to **Settings**
2. Click **Shop Settings** tab
3. Update:
   - Shop Name
   - Address
   - Phone
   - Email
4. Click **Save Changes**

### Task 2: Add Multiple Products
1. Go to **Inventory**
2. Click **Add Product** multiple times
3. Recommended sample products:
   - Rice varieties (10kg, 5kg bags)
   - Oil (cooking oil, coconut oil)
   - Sugar (1kg packets)
   - Flour (wheat, rice flour)
   - Spices (salt, pepper, etc.)
   - Canned goods
   - Beverages

### Task 3: Configure Printer
1. Go to **Settings > Shop Settings**
2. Check **Enable Printer**
3. Select your printer name from dropdown
4. Adjust paper width if needed (usually 80mm)
5. Test print a receipt

### Task 4: Train Cashier Users
1. Go to **Settings > User Management**
2. Add new user with cashier role
3. Share credentials with cashier
4. Cashier can access: POS tab only (or dashboard)

---

## Performance Tips

### For Smooth Operation
- Keep product database under 10,000 items
- Archive old transactions (monthly)
- Clear browser cache if using web version
- Run on a modern Windows 10/11 machine

### For Better Reports
- Review daily reports end of shift
- Check low stock alerts weekly
- Analyze best sellers monthly

---

## Troubleshooting Quick Fixes

### Problem: Forgot Password
**Solution**: Edit database directly or reset users table

### Problem: Product Not Found
**Solution**: Check barcode spelling, try search by name

### Problem: Print Not Working
**Solution**: 
- Check printer is online
- Verify printer name in settings
- Try Windows print dialog directly

### Problem: Slow Performance
**Solution**:
- Delete old sales (archive)
- Rebuild index on products table
- Close other apps

---

## Next Steps

After setup, consider:
1. ✅ Bulk import products from CSV (coming soon)
2. ✅ Set up daily backup schedule
3. ✅ Train staff on POS usage
4. ✅ Configure backup thermal printer
5. ✅ Set up monthly reconciliation process

---

## Need Help?

Check the main **README.md** for:
- Feature documentation
- Database schema details
- Architecture overview
- API reference

---

Enjoy using Randil Grocery POS! 🛒
