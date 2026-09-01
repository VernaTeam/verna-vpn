import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLang { fa, en }

class S {
  final AppLang lang;
  const S(this.lang);

  bool get isFa => lang == AppLang.fa;
  String _t(String fa, String en) => isFa ? fa : en;

  String get appName => _t('ورنا وی‌پی‌ان', 'Verna VPN');
  String get appTagline =>
      _t('کانفیگ‌های رایگان و تست‌شده', 'Free, tested configs');

  String get tabAll => _t('همه', 'All');
  String get tabText => _t('متنی', 'URI');
  String get tabFile => _t('فایلی', 'File');

  String get copy => _t('کپی', 'Copy');
  String get connect => _t('اتصال', 'Connect');

  // -- tunnel screen ---------------------------------------------------
  String get statusConnected => _t('متصل', 'Connected');
  String get statusDisconnected => _t('قطع', 'Not connected');
  String get statusPreparing => _t('در حال آماده‌سازی', 'Getting ready');
  String get statusSearching =>
      _t('در حال یافتن سرور سالم', 'Finding a working server');
  String get statusFailed => _t('اتصال برقرار نشد', 'Could not connect');

  String get autoSelect => _t('انتخاب خودکار', 'Automatic');
  String get bestAvailable =>
      _t('بهترین سرور در دسترس', 'Best available server');

  String get statDownload => _t('دانلود', 'Download');
  String get statUpload => _t('آپلود', 'Upload');
  String get statPing => _t('پینگ', 'Ping');
  String get tabHome => _t('خانه', 'Home');
  String get tabServers => _t('سرورها', 'Servers');
  String get tabStats => _t('آمار', 'Stats');
  String get tabConnect => _t('اتصال', 'Connect');
  String get tabUsage => _t('مصرف', 'Usage');
  String get tabPlan => _t('اشتراک', 'Plan');

  String get usage => _t('مصرف', 'Usage');
  String get lastFourteenDays => _t('۱۴ روز گذشته', 'Last 14 days');
  String get thisSession => _t('این جلسه', 'This session');
  String get today => _t('امروز', 'today');
  String get comparedToBusiestDay =>
      _t('نسبت به پرمصرف‌ترین روز', 'compared with the busiest day');
  String get usageEmpty =>
      _t('هنوز چیزی از تونل عبور نکرده', 'Nothing has gone through the tunnel yet');
  String get sessionDuration => _t('مدت اتصال', 'Session');
  String get upload => _t('آپلود', 'Upload');
  String get duration => _t('مدت', 'Duration');
  String get statData => _t('داده', 'Data');
  String get securelyConnected =>
      _t('اتصال شما امن است', 'You are securely connected');
  String get disconnect => _t('قطع اتصال', 'Disconnect');
  String get protected => _t('محافظت‌شده', 'Protected');
  String get exitAddress => _t('آدرس خروجی', 'Exit address');
  String get statsWhenConnected => _t(
        'وقتی متصل شدی، آمار اینجا می‌آید',
        'Statistics appear once you are connected',
      );
  String get openInTelegram => _t('اتصال در تلگرام', 'Open in Telegram');
  String get telegramProxy => _t('پروکسی تلگرام', 'Telegram proxy');
  String get telegramOnly => _t(
        'فقط تلگرام را تونل می‌کند، نه کل گوشی را',
        'Tunnels Telegram only, not the whole device',
      );
  String get ping => _t('پینگ', 'Ping');
  String get notTested => _t('تست نشده', 'Not tested');

  // Wording from the design handoff, kept as it was written there rather than
  // paraphrased: the Persian was authored alongside the English and reads as
  // one voice.
  String get change => _t('تغییر', 'Change');
  String get autoMeta => _t('خودکار · بر اساس پینگ', 'AUTO · by measured ping');
  String get hintOff => _t('اتصال امن ورنا', 'Secure Verna tunnel');
  String get hintBusy => _t('در حال یافتن سرور…', 'Finding a server…');
  String get hintOn => _t('برای قطع لمس کن', 'Tap to disconnect');
  String get failHint => _t('برای تلاش دوباره لمس کن', 'Tap to try again');
  String get failTitle =>
      _t('سرور در دسترس نبود', 'Could not reach a server');
  String get otherServer => _t('سرور دیگر', 'Other server');
  String get permissionDenied =>
      _t('اجازهٔ VPN داده نشد', 'VPN permission denied');
  String get fetchFailed =>
      _t('لیست سرورها دریافت نشد', 'Could not fetch the server list');
  String get noCandidates =>
      _t('سرور قابل استفاده‌ای نبود', 'No usable servers');
  String get moreActions => _t('گزینه‌های بیشتر', 'More');
  String get details => _t('جزئیات', 'Details');
  String get unknownCountry => _t('نامشخص', 'Unknown');
  String get testedHere => _t('تست‌شده روی این گوشی', 'Tested on this device');
  String get testingNow => _t('در حال تست', 'Testing');
  String get workingServers => _t('سرور سالم', 'working');
  String get blocked => _t('مسدود', 'Blocked');
  String get noTraffic => _t('بدون عبور', 'No traffic');
  String get testServers => _t('تست سرورها', 'Test servers');
  String testingProgress(int done, int total) =>
      _t('تست $done از $total…', 'Testing $done of $total…');
  String testedResult(int working, int total) => _t(
        '$working از $total سرور از اینجا کار می‌کند',
        '$working of $total work from here',
      );
  String get testWhileConnected => _t(
        'برای تست، اول قطع کن',
        'Disconnect first to test servers',
      );
  String get lastVerified => _t('آخرین تأیید', 'Last verified');
  String get justNow => _t('همین الان', 'just now');
  String minutesAgo(int m) => _t('$m دقیقه پیش', '$m min ago');
  String hoursAgo(int h) => _t('$h ساعت پیش', '$h h ago');

  String get configList => _t('فهرست کانفیگ‌ها', 'Config list');
  String get chooseLocation => _t('انتخاب کشور', 'Choose location');
  String get diagnostics => _t('عیب‌یابی', 'Diagnostics');
  String get diagApp => _t('اپلیکیشن', 'App');
  String get diagDevice => _t('دستگاه', 'Device');
  String get diagNetwork => _t('شبکه', 'Network');
  String get diagServer => _t('سرور', 'Server');
  String get diagEvents => _t('رویدادها', 'Events');
  String get diagNoEvents =>
      _t('هنوز رویدادی ثبت نشده', 'Nothing logged yet');
  String get clear => _t('پاک‌کردن', 'Clear');
  String get unreachable => _t('در دسترس نیست', 'unreachable');
  String selectedCount(int n) => _t('$n انتخاب‌شده', '$n selected');
  String get checkingServers =>
      _t('در حال بررسی سرورها…', 'Checking servers…');
  String get searchCountry => _t('جستجوی کشور', 'Search country');
  String get refresh => _t('به‌روزرسانی', 'Refresh');
  String get retry => _t('تلاش دوباره', 'Try again');
  String get noSearchResults =>
      _t('کشوری پیدا نشد', 'No country matches that');
  String get noVerifiedCountries => _t(
        'فعلاً هیچ کشوری سرور تأییدشده ندارد',
        'No country has a verified server right now',
      );
  String serversAvailable(int count) => _t(
        '$count سرور تأییدشده',
        '$count verified servers',
      );
  String get settings => _t('تنظیمات', 'Settings');

  String get msgFetchingList =>
      _t('در حال گرفتن فهرست سرورها…', 'Fetching server list…');
  String get msgFetchFailed =>
      _t('خطا در گرفتن فهرست سرورها', 'Could not fetch the server list');
  String get msgQuickCheck =>
      _t('بررسی سریع سرورها…', 'Quick-checking servers…');
  String get msgPermissionDenied =>
      _t('اجازهٔ VPN داده نشد', 'VPN permission was denied');
  String get msgNoConfigs =>
      _t('کانفیگی برای اتصال پیدا نشد', 'No usable server was found');
  String get msgUnstable => _t('اتصال ناپایدار بود، دوباره تلاش کن',
      'The connection was unstable -- try again');
  String get msgStopped => _t('قطع شد', 'Disconnected');

  String testingBatch(int count) => _t(
        'آزمایش $count سرور به‌صورت هم‌زمان…',
        'Testing $count servers at once…',
      );
  String get serverDidNotRespond => _t(
        'این سرور جواب نداد',
        "That server didn't respond",
      );
  String noneAnswered(int count) => _t(
        'هیچ‌کدام از $count سرور جواب نداد',
        'None of the $count servers responded',
      );
  String serverProgress(int done, int total) => _t(
        'سرور $done از $total',
        'Server $done of $total',
      );
  String connectError(Object error) =>
      _t('خطا در اتصال: $error', 'Connection error: $error');
  String get pressConnect => _t(
        'دکمهٔ اتصال را بزن',
        'Press Connect',
      );
  String get download => _t('دانلود', 'Download');
  String get filter => _t('فیلتر', 'Filter');
  String get clearFilter => _t('پاک‌کردن فیلتر', 'Clear filter');
  String get search => _t('جستجو...', 'Search...');
  String get about => _t('درباره', 'About');
  String get showQr => _t('نمایش QR', 'Show QR');
  String get qrTitle => _t('اسکن با اپ VPN', 'Scan with VPN app');
  String get qrHintText =>
      _t('این QR را با v2rayNG یا Hiddify اسکن کنید',
         'Scan this QR with v2rayNG or Hiddify');
  String get qrHintFile =>
      _t('اسکن کنید تا فایل دانلود شود', 'Scan to download the file');

  String get copied => _t('کپی شد ✓', 'Copied ✓');
  String get noConfigs => _t('کانفیگی یافت نشد', 'No configs found');
  String get error => _t('خطا در دریافت داده', 'Failed to load data');
  String get noApp => _t('اپ مناسب نصب نیست', 'No compatible app installed');
  String get downloading => _t('در حال دانلود...', 'Downloading...');
  String get downloaded => _t('دانلود شد', 'Downloaded');
  String get downloadFailed => _t('دانلود ناموفق', 'Download failed');

  String get filterByType => _t('فیلتر بر اساس پروتکل', 'Filter by protocol');
  String get filterByCountry => _t('فیلتر بر اساس کشور', 'Filter by country');
  String get allTypes => _t('همه پروتکل‌ها', 'All protocols');
  String get allCountries => _t('همه کشورها', 'All countries');

  String get protocol => _t('پروتکل', 'Protocol');
  String get country => _t('کشور', 'Country');
  String get quality => _t('کیفیت', 'Quality');
  String get recommendedApp => _t('اپ پیشنهادی', 'Recommended app');
  String get configContent => _t('محتوای کانفیگ', 'Config content');
  String get fileType => _t('نوع فایل', 'File type');

  // Quality labels
  String get qHigh => _t('عالی', 'High');
  String get qMedium => _t('متوسط', 'Medium');
  String get qLow => _t('ضعیف', 'Low');
  String get qUnknown => _t('نامشخص', 'Unknown');

  String get language => _t('زبان', 'Language');
  String get persian => _t('فارسی', 'Persian');
  String get english => _t('انگلیسی', 'English');
  String get theme => _t('تم', 'Theme');
  String get themeLight => _t('روشن', 'Light');
  String get themeDark => _t('تاریک', 'Dark');
  String get themeSystem => _t('سیستم', 'System');
  String get clearCache => _t('پاک کردن کش', 'Clear cache');
  String get cacheCleared => _t('کش پاک شد', 'Cache cleared');
  String get telegramChannel => _t('کانال تلگرام', 'Telegram channel');
  String get appearance => _t('ظاهر', 'Appearance');
  String get connection => _t('اتصال', 'Connection');
  String get maintenance => _t('درباره و نگهداری', 'About & maintenance');
  String get autoConnect => _t('اتصال خودکار', 'Auto-connect');
  String get autoConnectHint =>
      _t('با باز شدن برنامه وصل شو', 'Connect as soon as the app opens');
  String get killSwitch => _t('قطع اضطراری', 'Kill switch');
  String get killSwitchHint => _t(
      'اگر تونل قطع شد، اینترنت را ببند',
      'Block traffic if the tunnel drops');
  String get splitTunneling => _t('تونل انتخابی', 'Split tunneling');
  String get splitTunnelingHint =>
      _t('انتخاب اینکه کدام برنامه‌ها از تونل بروند',
         'Choose which apps use the tunnel');
  String get lanAccess => _t('دسترسی به شبکه محلی', 'Local network access');
  String get lanAccessHint => _t(
      'دستگاه‌های شبکه خانگی بدون تونل',
      'Reach devices on your own network directly');
  String get notBuiltYet => _t('به‌زودی', 'Soon');
  String get dnsLabel => _t('DNS', 'DNS');
  String get dnsHint =>
      _t('از طریق تونل، رمزگذاری‌شده', 'Encrypted, through the tunnel');
  String get selectionLabel => _t('انتخاب سرور', 'Server selection');
  String get selectionHint => _t(
      'سریع‌ترین سرور بر اساس تست همین دستگاه',
      'Fastest server, by the test run on this device');
  String get resetUsage => _t('پاک کردن آمار مصرف', 'Clear usage history');
  String get resetUsageHint =>
      _t('نمودار ۱۴ روزه از این دستگاه', 'The 14-day chart on this device');
  String get version => _t('نسخه', 'Version');

  String get plan => _t('اشتراک', 'Subscription');
  String get planFree => _t('رایگان', 'Free');
  String get planSoon => _t('به‌زودی فعال می‌شود', 'Coming soon');
  String get planHeadline =>
      _t('اشتراک ویژه', 'Verna Premium');
  String get planCurrent => _t('اشتراک فعلی · رایگان', 'Current plan · Free');
  String get planActive => _t('فعال', 'Active');
  String get planData => _t('حجم', 'Data');
  String get planDays => _t('اعتبار', 'Validity');
  String get planPrice => _t('هزینه', 'Cost');
  String get planBody => _t(
        'در حال حاضر همه‌ی امکانات برنامه رایگان و بدون محدودیت است. '
        'اشتراک ویژه بعداً اینجا اضافه می‌شود.',
        'Everything in the app is free and unlimited right now. '
        'A premium plan will appear here later.',
      );

  String get configsLabel => _t('کانفیگ', 'configs');
  String get textLabel => _t('متنی', 'text');
  String get fileLabel => _t('فایلی', 'file');
  String daysAgo(int d) => _t('$d روز پیش', '${d}d ago');
}

const _kLangKey = 'app_lang';

class LangNotifier extends AsyncNotifier<AppLang> {
  @override
  Future<AppLang> build() async {
    final prefs = await SharedPreferences.getInstance();
    // English unless the user has chosen otherwise. The app ships publicly,
    // so Persian is a preference rather than the default.
    return prefs.getString(_kLangKey) == 'fa' ? AppLang.fa : AppLang.en;
  }

  Future<void> setLang(AppLang lang) async {
    state = AsyncData(lang);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLangKey, lang == AppLang.en ? 'en' : 'fa');
  }
}

final langProvider =
    AsyncNotifierProvider<LangNotifier, AppLang>(LangNotifier.new);

final stringsProvider = Provider<S>((ref) {
  final lang = ref.watch(langProvider).valueOrNull ?? AppLang.en;
  return S(lang);
});
