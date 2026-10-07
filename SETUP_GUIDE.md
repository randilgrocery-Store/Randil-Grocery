# Randil Grocery POS - Complete Setup & Usage Guide

## ✅ Current Status
The Randil Grocery POS system is now **fully functional** with SQLite database integration for Windows!

---

## 🔐 Login Credentials

The system comes with two default user accounts pre-configured:

### Admin Account
- **Username**: `admin`
- **Password**: `admin123`
- **Role**: Administrator (full access to all features)

### Cashier Account
- **Username**: `cashier`
- **Password**: `cashier123`
- **Role**: Cashier (access to POS and sales)

---

## 📦 System Architecture

### Database Setup
- **Type**: SQLite (Local, offline-first)
- **Location**: `%APPDATA%/randil_grocery_pos.db`
- **Initialization**: Automatic on first run
- **Tables**:
  - `users` - User accounts and authentication
  - `products` - Inventory items
  - `sales` - Transaction records
  - `sales_items` - Sale line items
  - `stock_history` - Stock movement tracking
  - `shop_settings` - Configuration

### Technology Stack
- **Framework**: Flutter (Windows Desktop)
- **State Management**: Provider
- **Database**: SQLite with sqflite_common_ffi
- **UI Framework**: Material Design 3
- **Local Storage**: SharedPreferences for session management

---

## 🚀 Running the Application

### Start the App
```bash
cd "c:\Users\jerus\Desktop\Randil Grocery POS"
flutter run -d windows
```

### Hot Reload (Code changes only)
Press `r` in the terminal

### Hot Restart (Full rebuild)
Press `R` in the terminal

### Quit the App
Press `q` in the terminal

---

## 📱 Main Features

### 1. **Authentication** 🔐
- Login with credentials (admin or cashier accounts)
- Session persistence
- Role-based access control
- Logout functionality

### 2. **Point of Sale (POS)** 🛒
- Fast billing interface
- Add items to cart
- Adjust quantities
- View subtotal, discounts, and total
- Calculate balance
- Process transactions

### 3. **Inventory Management** 📦
- View all products in grid/list view
- **Add New Product**:
  - Product Name
  - Barcode (unique identifier)
  - Category
  - Buying Price
  - Selling Price
  - Stock Quantity
- Edit existing products
- Delete products
- Search by name or barcode
- Filter by category
- Low stock alerts

### 4. **Reports & Analytics** 📊
- Daily sales reports
- Monthly revenue summaries
- Top-selling items
- Daily/monthly transaction analysis
- Revenue trends

### 5. **Settings** ⚙️
- Shop information management
- Printer configuration
- User management
- System preferences

### 6. **Dashboard** 📈
- Key metrics at a glance
- Total products
- Low stock items
- Daily revenue
- Transaction count

---

## 🎯 How to Add Products

### Method 1: Via Inventory Screen
1. Go to **Inventory** tab
2. Click **+ Add Product** button
3. Fill in the details:
   - Product Name (e.g., "Rice - 10kg")
   - Barcode (e.g., "12345678")
   - Category (e.g., "Grocery")
   - Buying Price (e.g., 500)
   - Selling Price (e.g., 650)
   - Quantity in Stock (e.g., 50)
4. Click **Add** button
5. Product appears in inventory list

### Example Products to Add:
```
1. Product: Rice (1kg)
   Barcode: RIC001
   Category: Grocery
   Buying Price: 45
   Selling Price: 65

2. Product: Sugar (500g)
   Barcode: SUG001
   Category: Grocery
   Buying Price: 20
   Selling Price: 30

3. Product: Oil (1L)
   Barcode: OIL001
   Category: Oils
   Buying Price: 80
   Selling Price: 120
```

---

## 📝 How to Make a Sale

1. **Go to POS Screen**
   - Click the "POS" tab on the sidebar

2. **Add Items to Cart**
   - Search for product by name or barcode
   - Click on product or scan barcode
   - Enter quantity

3. **Review Cart**
   - See all items added
   - Adjust quantities if needed
   - View subtotal

4. **Checkout**
   - View total amount
   - Enter amount received
   - System calculates balance
   - Click "Process Sale"

5. **Receipt**
   - Receipt is generated
   - Stock is automatically deducted

---

## 🐛 Troubleshooting

### Issue: App won't start
**Solution**: 
- Clean build: `flutter clean` then `flutter pub get`
- Rebuild: `flutter run -d windows`

### Issue: Database locked
**Solution**:
- Close all instances of the app
- Delete `%APPDATA%/randil_grocery_pos.db`
- Restart the app

### Issue: Can't login
**Solution**:
- Ensure database initialized properly
- Check user credentials (admin/admin123 or cashier/cashier123)
- Clear app data and restart

### Issue: Products not showing
**Solution**:
- Make sure products were added via. Inventory screen
- Check database isn't read-only
- Try hot restart with `R` key

---

## 📂 Project Structure

```
lib/
├── main.dart                    # App entry point
├── core/                        # Constants & utilities
├── data/
│   ├── database/               # SQLite database service
│   ├── models/                 # Data models (Product, User, Sale)
│   └── services/               # Business logic (Auth, Print)
└── presentation/
    ├── providers/              # State management (Provider)
    ├── screens/                # UI screens
    └── widgets/                # Reusable components
```

---

## 🔄 Data Flow

```
User Input → Screens → Providers → Services → Database → Local Storage
    ↑                                                         ↓
    └─────────────────────────────────────────────────────────┘
```

---

## 💾 Database Schema

### Users Table
- `id` - Unique identifier
- `username` - Login username (unique)
- `password` - Password hash
- `role` - Admin or Cashier
- `fullName` - Display name
- `isActive` - Account status

### Products Table
- `id` - Unique product ID
- `name` - Product name
- `barcode` - Barcode (unique)
- `category` - Product category
- `buyingPrice` - Cost price
- `sellingPrice` - Sale price
- `quantity` - Stock quantity
- `createdAt` - Created timestamp
- `updatedAt` - Last modified timestamp

### Sales Table
- `id` - Transaction ID
- `cashierId` - Cashier user ID
- `cashierName` - Cashier name
- `items` - JSON array of sale items
- `subtotal` - Items total
- `totalDiscount` - Discount amount
- `totalAmount` - Final total
- `amountReceived` - Cash received
- `saleDate` - Date/time

---

##  🎨 UI/UX Features

- ✅ Material Design 3 theme
- ✅ Responsive layout for desktop
- ✅ Smooth animations and transitions
- ✅ Dark/Light theme support
- ✅ Green grocery-themed colors
- ✅ Intuitive sidebar navigation
- ✅ Real-time data updates

---

## 🛠️ Development Notes

### Adding New Features
1. Create model in `data/models/`
2. Add database methods in `data/database/database_service.dart`
3. Create provider in `presentation/providers/`
4. Design screen in `presentation/screens/`
5. Update navigation in sidebar

### Database Queries
- Products: CRUD operations
- Users: Authentication queries
- Sales: Transaction logging
- Reports: Aggregation queries

### State Management
- **ProductProvider**: Inventory management
- **AuthProvider**: User authentication
- **SalesProvider**: Cart & transactions
- **ReportsProvider**: Analytics data
- **SettingsProvider**: App configuration

---

## 📞 Support & Next Steps

### To Extend the System:
1. Add **Customer Management**
   - Track customer info
   - Loyalty points system
   - Credit/Debit tracking

2. Add **Multiple Users**
   - Admin can create/delete users
   - User performance tracking
   - Shift management

3. Cloud Sync
   - Sync sales to cloud
   - Backup data automatically
   - Multi-location support

4. Advanced Reports
   - Profit/Loss analysis
   - Product performance
   - Sales trends

5. Barcode Integration
   - Generate barcodes
   - Barcode scanner support
   - Label printing

---

## ✨ Key Features Implemented

- ✅ SQLite Database Integration
- ✅ User Authentication (Admin/Cashier)
- ✅ Product Management (Add/Edit/Delete)
- ✅ Shopping Cart
- ✅ Sales Transaction Processing
- ✅ Inventory Tracking
- ✅ Daily/Monthly Reports
- ✅ Stock Alerts
- ✅ Material Design 3 UI
- ✅ Windows Desktop Support
- ✅ Local Data Storage
- ✅ Session Management

---

## 🎉 You're All Set!

Your Randil Grocery POS system is ready to use. Login with the credentials above and start managing your grocery store!

**Happy Selling! 🛍️**
