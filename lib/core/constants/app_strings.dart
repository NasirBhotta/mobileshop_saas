class AppStrings {
  const AppStrings._();

  // ═══════════════════════════════════════
  // App General
  // ═══════════════════════════════════════
  static const String appName = 'MobileShop SaaS';

  // ═══════════════════════════════════════
  // Intro Screens
  // ═══════════════════════════════════════
  static const String introSkip = 'Skip';
  static const String introNext = 'Next';
  static const String introGetStarted = 'Get Started';

  static const String intro1Title = 'Apni Dukaan,\nDigital Bano';
  static const String intro1Desc =
      'Inventory, sales, aur customers — sab kuch ek hi app mein, kahin se bhi manage karein.';

  static const String intro2Title = 'Offline Bhi,\nOnline Bhi';
  static const String intro2Desc =
      'Internet na ho tab bhi sale karein. Connection wapas aate hi sab automatically sync ho jata hai.';

  static const String intro3Title = 'Inventory, IMEI,\nRepairs — Sab Ek Jagah';
  static const String intro3Desc =
      'Mobile phones ka stock track karein, IMEI verify karein, aur repair tickets manage karein.';

  static const String intro4Title = 'Reports Dekho,\nBusiness Badhao';
  static const String intro4Desc =
      'Sales aur profit ki detailed reports dekhein — apne business ke faisle data se karein.';

  // ═══════════════════════════════════════
  // Login Screen
  // ═══════════════════════════════════════
  static const String loginTitle = 'Welcome Back';
  static const String loginSubtitle = 'Apni dukaan ka dashboard access karein';
  static const String loginButton = 'Login';
  static const String loginWithOtp = 'Login with OTP instead';
  static const String orDivider = 'OR';
  static const String continueWithGoogle = 'Continue with Google';
  static const String noAccount = "Account nahi hai? ";
  static const String signUpLink = 'Sign Up';

  // ═══════════════════════════════════════
  // Signup Screen
  // ═══════════════════════════════════════
  static const String signupTitle = 'Account Banayein';
  static const String signupSubtitle =
      'Apni dukaan ko digital banane ka pehla kadam';
  static const String signupButton = 'Sign Up';
  static const String alreadyHaveAccount = 'Pehle se account hai? ';
  static const String loginLink = 'Login';

  // ═══════════════════════════════════════
  // Form Fields & Labels
  // ═══════════════════════════════════════
  static const String fieldEmail = 'Email';
  static const String fieldPassword = 'Password';
  static const String fieldConfirmPassword = 'Confirm Password';
  static const String fieldFullName = 'Pura Naam';
  static const String fieldPhone = 'Phone Number';

  static const String hintEmail = 'you@example.com';
  static const String hintPassword = '••••••••';
  static const String hintFullName = 'Muhammad Ali';
  static const String hintPhone = '03XX-XXXXXXX';

  // ═══════════════════════════════════════
  // Validation Messages
  // ═══════════════════════════════════════
  static const String errorEmailRequired = 'Email required hai';
  static const String errorEmailInvalid = 'Valid email likhein';
  static const String errorPasswordRequired = 'Password required hai';
  static const String errorPasswordTooShort = 'Kam az kam 6 characters chahiye';
  static const String errorPasswordMismatch = 'Passwords match nahi karte';
  static const String errorNameRequired = 'Naam likhna zaroori hai';
  static const String errorPhoneInvalid = 'Valid phone number likhein';
  static const String errorOtpInvalid = 'Code sahi nahi hai, dobara try karein';

  // ═══════════════════════════════════════
  // OTP Screen
  // ═══════════════════════════════════════
  static const String otpTitle = 'OTP Verification';
  static const String otpSubtitle =
      'Apne phone par bheja gaya code darj karein';
  static const String otpVerifyButton = 'Verify Karein';
  static const String otpResend = 'Code dobara bhejein';

  // ═══════════════════════════════════════
  // Generic / Reusable
  // ═══════════════════════════════════════
  static const String loading = 'Loading...';
  static const String somethingWentWrong =
      'Kuch ghalat ho gaya, dobara try karein';
  static const String retry = 'Dobara Koshish Karein';
  static const String logout = 'Logout';
  static const String logoutTitle = 'Logout karein?';
  static const String logoutMessage =
      'Aapka session is device se close ho jayega.';
  static const String cancel = 'Cancel';

  // ═══════════════════════════════════════
  // Shop Setup
  // ═══════════════════════════════════════
  static const String setupTitle = 'Apni Dukaan Set Up Karein';
  static const String setupStepOf = 'Step %d of %d';

  // Step 1: Basics
  static const String setupStep1Title = 'Dukaan Ki Basic Maloomat';
  static const String setupStep1Subtitle =
      'Apni dukaan ka naam aur location batayein';
  static const String fieldShopName = 'Dukaan Ka Naam';
  static const String hintShopName = 'Ali Mobile Center';
  static const String fieldCity = 'Shehar';
  static const String hintCity = 'Lahore';
  static const String fieldAddress = 'Pura Address';
  static const String hintAddress = 'Dukaan ka address likhein';
  static const String errorShopNameRequired =
      'Dukaan ka naam likhna zaroori hai';
  static const String errorCityRequired = 'Shehar likhna zaroori hai';
  static const String errorAddressRequired = 'Address likhna zaroori hai';

  // Step 2: Business Details
  static const String setupStep2Title = 'Business Ki Tafseelat';
  static const String setupStep2Subtitle =
      'Apna business type aur branches batayein';
  static const String fieldBusinessType = 'Business Type';
  static const String fieldBranchCount = 'Kitni Branches Hain?';
  static const String businessTypeMobile = 'Mobile Phone Shop';
  static const String businessTypeElectronics = 'Electronics Shop';
  static const String businessTypeBoth = 'Mobile + Electronics';
  static const String errorBusinessTypeRequired = 'Business type select karein';

  // Step 3: Confirmation
  static const String setupStep3Title = 'Sab Theek Hai?';
  static const String setupStep3Subtitle =
      'Ek baar check kar lein, phir setup complete karein';
  static const String confirmShopName = 'Dukaan Ka Naam';
  static const String confirmCity = 'Shehar';
  static const String confirmAddress = 'Address';
  static const String confirmBusinessType = 'Business Type';
  static const String confirmBranches = 'Branches';

  // Buttons
  static const String setupNext = 'Agla Step';
  static const String setupBack = 'Pichla Step';
  static const String setupFinish = 'Setup Complete Karein';

  // ═══════════════════════════════════════
  // Dashboard
  // ═══════════════════════════════════════
  static const String navDashboard = 'Dashboard';
  static const String navInventory = 'Inventory';
  static const String navPos = 'Sale';
  static const String navRepairs = 'Repairs';
  static const String navMore = 'More';
  static const String navReports = 'Reports';
  static const String navCustomers = 'Customers';
  static const String navSettings = 'Settings';
  static const String navSuppliers = 'Suppliers';
  static const String navExpenses = 'Expenses';
  static const String navAccounts = 'Accounts';

  static const String dashboardTitle = 'Dashboard';
  static const String dashboardWelcome = 'Khush Aamdeed';
  static const String dashboardTodaySales = 'Aaj Cash Received';
  static const String dashboardTotalStock = 'Total Stock';
  static const String dashboardActiveRepairs = 'Active Repairs';
  static const String dashboardLowStock = 'Low Stock Items';
  static const String dashboardQuickActions = 'Quick Actions';
  static const String dashboardRecentSales = 'Recent Sales';
  static const String dashboardOverallSales = 'Cash Received';
  static const String dashboardOverallProfit = 'Realized Profit';
  static const String dashboardTotalUdhar = 'Total Udhar';
  static const String dashboardUdharCustomers = 'Udhar Customers';
  static const String dashboardSendReminder = 'Send Reminder';

  static const String actionNewSale = 'Naya Sale';
  static const String actionAddProduct = 'Product Add Karo';
  static const String actionNewRepair = 'Naya Repair';
  static const String actionAddExpense = 'Expense Add Karo';
  static const String actionAccountEntry = 'Account Entry';

  static const String fieldBranchName = 'Branch Ka Naam';
  static const String setupStep4Title = 'Sab Theek Hai?';
  static const String setupStep4Subtitle =
      'Ek baar check kar lein, phir setup complete karein';

  // ═══════════════════════════════════════
  // Inventory
  // ═══════════════════════════════════════s
  static const String inventoryTitle = 'Inventory';
  static const String inventoryEmpty = 'Koi product nahi mila';
  static const String inventoryEmptyDesc = 'Pehla product add karein';
  static const String inventoryAddProduct = 'Product Add Karein';
  static const String inventoryEditProduct = 'Product Edit Karein';
  static const String inventorySearch = 'Product dhoondein...';
  static const String inventoryAllCategories = 'Sab';

  // Product Form
  static const String fieldProductName = 'Product Ka Naam';
  static const String fieldSku = 'SKU (Optional)';
  static const String fieldDescription = 'Description (Optional)';
  static const String fieldSalePrice = 'Sale Price (₨)';
  static const String fieldCostPrice = 'Cost Price (₨)';
  static const String fieldCategory = 'Category';
  static const String fieldImeiTracked = 'IMEI Tracking On Karein';

  static const String hintProductName = 'Samsung Galaxy A15';
  static const String hintSku = 'SAM-A15-BLK';
  static const String hintSalePrice = '0.00';
  static const String hintCostPrice = '0.00';

  static const String errorProductNameRequired = 'Product naam zaroori hai';
  static const String errorSalePriceInvalid = 'Valid price likhein';
  static const String errorCostPriceInvalid = 'Valid cost likhein';

  // Categories
  static const String categoriesTitle = 'Categories';
  static const String categoryAddNew = 'Nai Category';
  static const String fieldCategoryName = 'Category Naam';
  static const String hintCategoryName = 'Mobile Phones';
  static const String errorCategoryNameRequired = 'Category naam zaroori hai';

  // Stock
  static const String stockAdjust = 'Stock Adjust Karein';
  static const String stockIn = 'Stock In';
  static const String stockOut = 'Stock Out';
  static const String fieldQuantity = 'Quantity';
  static const String fieldReason = 'Wajah (Optional)';
  static const String currentStock = 'Maujuda Stock';

  static const String stockAdjustButton = 'Adjustment Save Karein';
  static const String stockAdjustSuccess = 'Stock update ho gaya!';
  static const String fieldAdjustmentType = 'Adjustment Type';
  static const String fieldReasonNote = 'Wajah Ki Tafseelat';
  static const String hintReasonNote = 'Mazeed detail likhein...';
  static const String errorQuantityRequired = 'Quantity likhein';
  static const String errorQuantityInvalid = 'Quantity 1 ya zyada honi chahiye';
  static const String errorReasonNoteRequired =
      '"Other" select kiya hai — wajah likhna zaroori hai';

  // Search + Filter + Sort
  static const String searchProducts = 'Product dhoondein...';
  static const String sortBy = 'Sort By';
  static const String sortNameAZ = 'Naam A-Z';
  static const String sortNameZA = 'Naam Z-A';
  static const String sortPriceLow = 'Price: Kam se Zyada';
  static const String sortPriceHigh = 'Price: Zyada se Kam';
  static const String sortStockLow = 'Stock: Kam se Zyada';
  static const String sortStockHigh = 'Stock: Zyada se Kam';
  static const String filterResults = 'Results';
  static const String noSearchResults = 'Koi product nahi mila';
  static const String noSearchResultsDesc = 'Alag naam ya SKU try karein';

  // ═══════════════════════════════════════
  // POS / Sales
  // ═══════════════════════════════════════

  // Screen Titles
  static const String posTitle = 'New Sale';
  static const String posHeldCarts = 'Held Carts';
  static const String posSaleComplete = 'Sale Complete';
  static const String posSalesHistory = 'Sales History';

  // Cart
  static const String cartEmpty = 'Cart empty hai';
  static const String cartEmptyDesc = 'Product search karein ya scan karein';
  static const String cartItems = 'Items';
  static const String cartTotal = 'Total';
  static const String cartSubtotal = 'Subtotal';
  static const String cartDiscount = 'Discount';
  static const String cartTax = 'Tax';
  static const String cartItemCount = 'items';

  // Product Search
  static const String searchProductsPos =
      'Product dhoondein ya SKU scan karein...';
  static const String noProductsFound = 'Koi product nahi mila';

  // Customer
  static const String attachCustomer = 'Customer Lagayen (Optional)';
  static const String customerSearch = 'Customer naam ya phone...';
  static const String customerNotFound = 'Customer nahi mila';
  static const String quickAddCustomer = 'Naya Customer Add Karein';
  static const String customerAttached = 'Customer laga diya';
  static const String customerRemoved = 'Customer hata diya';
  static const String fieldCustomerName = 'Customer Ka Naam';
  static const String fieldCustomerPhone = 'Phone Number';
  static const String fieldCustomerEmail = 'Email (Optional)';
  static const String hintCustomerName = 'Muhammad Ali';
  static const String errorCustomerNameRequired = 'Naam zaroori hai';

  // Payment
  static const String paymentTitle = 'Payment';
  static const String paymentMethod = 'Payment Method';
  static const String paymentSplit = 'Split Payment';
  static const String paymentCash = 'Cash';
  static const String paymentEasypaisa = 'EasyPaisa';
  static const String paymentJazzcash = 'JazzCash';
  static const String paymentCard = 'Card';
  static const String paymentRemaining = 'Remaining';
  static const String paymentEntered = 'Entered';
  static const String paymentExact = 'Exact change';
  static const String checkoutButton = 'Checkout Karein';
  static const String paymentComplete = 'Payment Complete ✓';
  static const String paymentIncomplete = 'Payment poori nahi hai';

  // Hold / Void
  static const String holdCart = 'Cart Hold Karein';
  static const String holdCartLabel = 'Cart Ka Naam (Optional)';
  static const String hintHoldLabel = 'Customer 1, Walk-in...';
  static const String holdSuccess = 'Cart hold ho gayi';
  static const String resumeCart = 'Resume Karein';
  static const String noHeldCarts = 'Koi held cart nahi';
  static const String noHeldCartsDesc = 'Hold ki hui carts yahan dikhengi';
  static const String voidCart = 'Cart Void Karein';
  static const String voidCartConfirm =
      'Kya aap yeh cart void karna chahte hain?';
  static const String voidReason = 'Void Ki Wajah (Optional)';
  static const String hintVoidReason = 'Galat items, customer na aaya...';
  static const String voidSuccess = 'Cart void ho gayi';
  static const String voidConfirmButton = 'Haan, Void Karein';

  // Discount
  static const String itemDiscount = 'Item Discount';
  static const String hintDiscount = '0';
  static const String errorDiscountInvalid = 'Valid discount likhein';
  static const String errorDiscountExceeds =
      'Discount price se zyada nahi ho sakta';

  // Sale Complete
  static const String saleCompleteTitle = 'Sale Complete! ✓';
  static const String saleCompleteAmount = 'Total Amount';
  static const String saleCompletePayments = 'Payments';
  static const String printReceipt = 'Receipt Print Karein';
  static const String shareReceipt = 'Receipt Share Karein';
  static const String newSale = 'Naya Sale';

  // Errors
  static const String errorCartEmpty = 'Cart mein koi item nahi';
  static const String errorStockInsufficient = 'Stock kam hai';
  static const String errorPaymentMismatch = 'Payment total match nahi karta';
  static const String errorCheckoutFailed =
      'Checkout fail ho gaya, dobara try karein';
}
