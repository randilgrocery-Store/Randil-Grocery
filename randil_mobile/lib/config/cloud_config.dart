/// Supabase project used by the shop.
///
/// Mirrors the desktop POS `CloudConfig` — the anon key is publishable by
/// design (Supabase RLS allows anon read on the dashboards tables), so the
/// phone app can read the shop's real data with no login.
class CloudConfig {
  CloudConfig._();

  static const String url = 'https://kmaduptkjjaxbgakpzsg.supabase.co';
  static const String anonKey =
      'sb_publishable_QQz_GIjUAR0hZKrm77fxqA_KIPu6Qvd';
  static const String shopId = 'main';
}