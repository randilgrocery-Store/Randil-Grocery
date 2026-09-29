/// Default Supabase project used by the POS + phone app.
///
/// The Cloud Sync settings screen is pre-filled with these values, so a shop
/// only has to run `docs/supabase_schema.sql` in the Supabase SQL Editor and
/// press "Save & Sync Now".
class CloudConfig {
  CloudConfig._();

  static const String url = 'https://kmaduptkjjaxbgakpzsg.supabase.co';
  static const String anonKey =
      'sb_publishable_QQz_GIjUAR0hZKrm77fxqA_KIPu6Qvd';
  static const String shopId = 'main';
}