class AppStrings {
  const AppStrings._();

  // ═══════════════════════════════════════
  // App General
  // ═══════════════════════════════════════
  static const String appName = 'Nizaaam';
  static const String navMobileServices = 'Mobile Services';

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
  static const String hintFullName = 'Nasir Bhutta';
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
  static const String dashboardTodaySales = 'Aaj ki sales';
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

  // Customer Management
  static const String customersTitle = 'Customers';
  static const String customerUnknownInitial = '?';
  static const String customerDetailSeparator = ' • ';
  static const String customerAdd = 'Add';
  static const String customerSearchHint = 'Search name, phone, email...';
  static const String customersEmpty = 'No customers yet';
  static const String customerCreditLimitTooltip = 'Credit limit';
  static const String customerLifetimeValue = 'Lifetime Value';
  static const String customerOutstanding = 'Outstanding';
  static const String customerCreditLimit = 'Credit Limit';
  static const String customerActiveRepairs = 'Active Repairs';
  static const String customerCreditLimitNotSet = 'Not set';
  static const String customerCreditExplanation =
      'Credit limit max khata allowance hai. Khata sale checkout par outstanding mein add hoti hai; Settle Dues se customer ki payment record hoti hai aur outstanding kam hota hai.';
  static const String customerSettleDues = 'Settle Dues';
  static const String customerPurchaseHistory = 'Purchase History';
  static const String customerNoPurchases = 'No purchases found';
  static const String customerSettlements = 'Settlements';
  static const String customerNoSettlements = 'No settlements yet';
  static const String customerAddTitle = 'Add Customer';
  static const String customerClose = 'Close';
  static const String customerFullNameLabel = 'Full name';
  static const String customerPhoneLabel = 'Phone';
  static const String customerEmailLabel = 'Email';
  static const String customerCreditLimitLabel = 'Credit limit (optional)';
  static const String customerCreditLimitPrefix = 'Rs ';
  static const String customerCreditLimitHelper =
      'Owner set kare. Blank ka matlab fixed limit nahi.';
  static const String customerNotesLabel = 'Notes';
  static const String customerSave = 'Save Customer';
  static const String customerSaveFailed = 'Customer save nahi hua';
  static const String customerCreditLimitTitle = 'Credit Limit';
  static const String customerLimitLabel = 'Limit';
  static const String customerClear = 'Clear';
  static const String customerSaveAction = 'Save';
  static const String customerCreditLimitSaveFailed =
      'Credit limit save nahi hui';
  static const String customerSettlementAmountLabel = 'Amount';
  static const String customerSettlementMethodLabel = 'Method';
  static const String customerReceivingAccountLabel = 'Receiving account';
  static const String customerCompatibleAccountRequired =
      'Accounts screen mein compatible account banayein.';
  static const String customerRecordSettlement = 'Record Settlement';
  static const String customerRecordingSettlement = 'Recording...';
  static const String customerSettlementAmountInvalid =
      'Valid settlement amount enter karein.';
  static const String customerSettlementExceedsDues =
      'Settlement current dues se zyada nahi ho sakti.';
  static const String customerSettlementSuccess =
      'Customer dues successfully settle ho gaye.';
  static const String customerSettlementSaveFailed =
      'Settlement save nahi hui. Dobara try karein.';
  static const String customerSettlementLedgerFailed =
      'Settlement ledger update nahi ho saka. Database migration apply karke dobara try karein.';
  static const String customerSettlementPermissionDenied =
      'Aap ke paas customer dues settle karne ki permission nahi hai.';
  static const String customerSettlementAccountInvalid =
      'Selected receiving account valid nahi hai.';
  static const String customerSettlementOffline =
      'Network issue hai. Settlement locally save ho gayi hai aur connection aane par sync ho jayegi.';
  static const String customerSettlementRetry =
      'Settlement save nahi hui. Please dobara try karein.';

  static String customerDue(double amount) =>
      'Due Rs ${amount.toStringAsFixed(0)}';
  static String customerMoney(double amount) =>
      'Rs ${amount.toStringAsFixed(0)}';
  static String customerInvoice(String id) => 'Invoice $id';
  static String customerSettlementDetails(String method, String createdAt) =>
      '$method • $createdAt';
  static String customerAccountSummary(String name, double balance) =>
      '$name • Rs ${balance.toStringAsFixed(0)}';

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

  // Repairs
  static const String repairsTitle = 'Repairs';
  static const String repairBack = 'Back';
  static const String repairCancel = 'Cancel';
  static const String repairClose = 'Close';
  static const String repairSync = 'Sync';
  static const String repairRetry = 'Retry';
  static const String repairCreateTicket = 'Create Repair Ticket';
  static const String repairTicketLabel = 'Repair Ticket';
  static const String repairNew = 'New Repair';
  static const String repairSaving = 'Saving...';
  static const String repairRequired = 'Required';
  static const String repairSomethingWentWrong = 'Something went wrong';
  static const String repairCustomerDetails = 'Customer Details';
  static const String repairCustomerDetailsSubtitle =
      'Customer ka basic info yahan save hoga.';
  static const String repairCustomerName = 'Customer name';
  static const String repairCustomerNameHint = 'Example: Ali Raza';
  static const String repairCustomerPhone = 'Customer phone optional';
  static const String repairCustomerPhoneHint = 'Example: 03001234567';
  static const String repairDeviceDetails = 'Device Details';
  static const String repairDeviceDetailsSubtitle =
      'Device ka model, IMEI aur optional inventory product link.';
  static const String repairLinkedProduct = 'Linked inventory product optional';
  static const String repairExternalDevice =
      'External device / no product link';
  static const String repairProductsLoadFailed =
      'Products load nahi ho sake. Ticket phir bhi external device ke tor par create ho sakta hai.';
  static const String repairDeviceBrand = 'Device brand';
  static const String repairDeviceBrandHint = 'Example: Samsung';
  static const String repairDeviceModel = 'Device model';
  static const String repairDeviceModelHint = 'Example: A15';
  static const String repairDeviceColor = 'Device color optional';
  static const String repairDeviceColorHint = 'Example: Black';
  static const String repairImeiOptional = 'IMEI optional';
  static const String repairImeiHint = 'Example: 356789XXXXXXXXX';
  static const String repairFaultDescription = 'Fault Description';
  static const String repairFaultDescriptionSubtitle =
      'Customer ne device mein jo problem batayi hai woh yahan likho.';
  static const String repairFaultIssue = 'Fault / issue';
  static const String repairFaultHint = 'Example: Charging nahi ho rahi';
  static const String repairChargeEstimate = 'Repair Charge Estimate';
  static const String repairChargeEstimateSubtitle =
      'Estimated service/labour charge; parts completion par automatically add honge.';
  static const String repairEstimatedServiceCharge =
      'Estimated service charge optional';
  static const String repairEstimatedServiceChargeHint = 'Example: 500';
  static const String repairEstimatedCompletion =
      'Estimated completion optional';
  static const String repairEstimateNote = 'Estimate note optional';
  static const String repairEstimateNoteHint =
      'Example: Parts available hone par confirm hoga';
  static const String repairSelectDate = 'Select date';
  static const String repairValidAmount = 'Enter valid amount';
  static const String repairAmountNotNegative = 'Amount cannot be negative';

  static const String repairCompleteTitle = 'Complete Repair';
  static const String repairCompletionInfo =
      'Parts are consumed and profit is finalized only after confirmation.';
  static const String repairAddPart = 'Add Part';
  static const String repairFinalBill = 'Final bill total (including parts)';
  static const String repairFinalBillHelper =
      'Parts + service charge - discount';
  static const String repairUseCalculatedTotal = 'Use calculated total';
  static const String repairManualTotalHelper =
      'Manually adjusted. Tap calculate to restore the suggested total.';
  static const String repairAdvancedCharges =
      'Optional advanced charges & costs';
  static const String repairServiceCharge = 'Repair / service charge';
  static const String repairDiscount = 'Discount';
  static const String repairCommission = 'Per-job commission';
  static const String repairOtherDirectCost = 'Other direct cost';
  static const String repairCompleting = 'Completing...';
  static const String repairConfirmCompletion = 'Confirm Completion';
  static const String repairInvalidCharge = 'Enter a valid charge.';
  static const String repairInvalidPartDetails =
      'Complete all part details with valid amounts.';
  static const String repairCompletionFailed = 'Repair could not be completed.';
  static const String repairInventory = 'Inventory';
  static const String repairDirectPurchase = 'Direct purchase';
  static const String repairPartName = 'Part name';
  static const String repairPurchaseSettlement = 'Purchase settlement';
  static const String repairCostAlreadyRecorded = 'Cost already recorded';
  static const String repairAddSupplierPayable = 'Add to supplier payable';
  static const String repairSupplier = 'Supplier';
  static const String repairQuantity = 'Qty';
  static const String repairUnitCost = 'Unit cost';
  static const String repairCustomerPrice = 'Customer price';
  static const String repairInventoryProduct = 'Inventory product';
  static const String repairInventorySearchHint = 'Search name, SKU or barcode';
  static const String repairTapInventorySearch = 'Tap to search inventory';
  static const String repairSearchInventoryPart = 'Search inventory part';
  static const String repairProductSearchHint =
      'Product name, SKU, barcode or category';
  static const String repairClearSearch = 'Clear search';
  static const String repairSearchInventoryPrompt =
      'Search to find an in-stock inventory item.';
  static const String repairTypeInventoryPrompt =
      'Type a product name, SKU or barcode.';
  static const String repairNoInventoryMatch =
      'No active in-stock product matched.';

  static const String repairsEmptyTitle = 'No Repairs';
  static const String repairsEmptyMessage = 'Abhi koi repair ticket nahi bana.';
  static const String repairsLoadFailed = 'Repairs load nahi ho sake';
  static const String repairUnableToLoad = 'Unable to load';
  static const String repairAll = 'All';
  static const String repairNoTicketNumber = 'No Ticket No';
  static const String repairNoDate = 'No date';
  static const String repairCustomer = 'Customer';
  static const String repairDevice = 'Device';
  static const String repairImei = 'IMEI';
  static const String repairStatus = 'Status';
  static const String repairServiceEstimate = 'Service Estimate';
  static const String repairFinalBillLabel = 'Final Bill';
  static const String repairReceivePayment = 'Receive Payment';
  static const String repairArchiveTicket = 'Archive Ticket';
  static const String repairNextStatus = 'Next status';
  static const String repairStatusNote = 'Status note optional';
  static const String repairUpdating = 'Updating...';
  static const String repairUpdateStatus = 'Update Status';
  static const String repairStatusUpdating =
      'Status update ho raha hai, please wait...';
  static const String repairStatusLocked =
      'Is ticket ka status ab change nahi ho sakta.';
  static const String repairStatusUpdateFailed =
      'Status update nahi ho saka. Koi record change nahi hua.';
  static const String repairReceivePaymentTitle = 'Receive Repair Payment';
  static const String repairAmount = 'Amount';
  static const String repairMethod = 'Method';
  static const String repairReceivingAccount = 'Receiving Account';
  static const String repairCompatibleAccountRequired =
      'Create a compatible account first.';
  static const String repairPaymentNote = 'Note optional';
  static const String repairReceivingPayment = 'Receiving Payment...';
  static const String repairPaymentReceived = 'Payment received';
  static const String repairReceiving = 'Receiving...';
  static const String repairReceive = 'Receive';
  static const String repairPaymentFailed = 'Payment receive nahi ho saki';
  static const String repairCancelRefundTitle = 'Cancel & refund repair';
  static const String repairRefundAccount = 'Refund from account / wallet';
  static const String repairRefundAccountRequired =
      'Customer refund ke liye valid account select karein.';
  static const String repairRefundBalanceLow =
      'Selected account mein customer refund ke liye balance kam hai.';
  static const String repairRefundBalanceUnavailable =
      'Kisi active account mein refund ke liye sufficient balance nahi hai.';
  static const String repairCancelPermissionDenied =
      'Aap ke paas repair cancel karne ki permission nahi hai.';
  static const String repairCancelFailed =
      'Repair cancel nahi ho saki. Records change nahi huay; dobara try karein.';
  static const String repairSupplierPaidPartBlocked =
      'Supplier ko paid part pehle resolve karein; phir repair cancel hogi.';
  static const String repairRefundAndCancel = 'Refund & Cancel';
  static const String repairArchiveTitle = 'Archive ticket?';
  static const String repairArchiveMessage =
      'Ticket list se hide ho ga. Financial history, payments, parts aur reversal records delete nahi honge.';
  static const String repairArchive = 'Archive';
  static const String repairRefundConfirmation =
      'Confirm karne par refund ledger, account balance, used inventory parts, supplier payable aur repair profit ek atomic transaction mein reverse honge.';

  static String repairTicketCreated(String ticketNumber) =>
      'Repair ticket $ticketNumber created';
  static String repairProductLabel(
    String name,
    String? sku,
    bool imeiTracked,
  ) =>
      '$name${sku?.isNotEmpty == true ? ' ($sku)' : ''}'
      '${imeiTracked ? ' • IMEI' : ''}';
  static String repairMoney(double amount) => 'Rs ${amount.toStringAsFixed(0)}';
  static String repairServiceEstimateAmount(double amount) =>
      'Service est. Rs ${amount.toStringAsFixed(0)}';
  static String repairStatusUpdated(String status) => 'Status $status ho gaya';
  static String repairStatusEmpty(String status) =>
      '$status status mein koi repair ticket nahi hai.';
  static String repairAccountBalance(String name, double amount) =>
      '$name • Rs ${amount.toStringAsFixed(0)}';
  static String repairRemaining(double amount) =>
      'Remaining Rs ${amount.toStringAsFixed(0)}';
  static String repairAmountRange(double remaining) =>
      'Enter an amount between Rs 1 and Rs ${remaining.toStringAsFixed(0)}.';
  static String repairAccountsLoadFailed(Object error) =>
      'Receiving accounts load nahi ho sake: $error';
  static String repairRefundAmount(double paid) =>
      'Customer ko Rs ${paid.toStringAsFixed(0)} refund karna zaroori hai.';
  static String repairStockAvailable(String name, int stock) =>
      '$name ka available stock $stock hai.';
  static String repairCustomerTotal(double amount) =>
      'Customer total: Rs ${amount.toStringAsFixed(0)}';
  static String repairPartsCustomerPrice(double amount) =>
      'Parts customer price: Rs ${amount.toStringAsFixed(0)}';
  static String repairPartsCost(double amount) =>
      'Parts cost: Rs ${amount.toStringAsFixed(0)}';
  static String repairGrossProfit(double amount) =>
      'Gross profit: Rs ${amount.toStringAsFixed(0)}';
  static String repairInventorySummary(int stock, double cost, String? sku) =>
      'Stock $stock • Cost Rs ${cost.toStringAsFixed(0)}'
      '${sku?.isNotEmpty == true ? ' • SKU $sku' : ''}';
  static String repairMatchingItems(int count) =>
      '$count matching items${count == 50 ? ' (top results)' : ''}';
  static String repairSku(String sku) => 'SKU $sku';
  static String repairCost(double amount) =>
      'Cost Rs ${amount.toStringAsFixed(0)}';
  static String repairStock(int stock) => 'Stock $stock';
  static String repairImeiValue(String imei) => 'IMEI: $imei';
  static String repairDeviceName(String brand, String model) => '$brand $model';
  static String repairDetailLabel(String label) => '$label: ';
  static String repairDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day-$month-${date.year}';
  }
}
