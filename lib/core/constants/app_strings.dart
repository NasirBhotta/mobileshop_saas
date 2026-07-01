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

  static const String dashboardTitle = 'Dashboard';
  static const String dashboardWelcome = 'Khush Aamdeed';
  static const String dashboardTodaySales = 'Aaj Ki Sales';
  static const String dashboardTotalStock = 'Total Stock';
  static const String dashboardActiveRepairs = 'Active Repairs';
  static const String dashboardLowStock = 'Low Stock Items';
  static const String dashboardQuickActions = 'Quick Actions';
  static const String dashboardRecentSales = 'Recent Sales';

  static const String actionNewSale = 'Naya Sale';
  static const String actionAddProduct = 'Product Add Karo';
  static const String actionNewRepair = 'Naya Repair';
  static const String actionAddExpense = 'Expense Add Karo';
}
