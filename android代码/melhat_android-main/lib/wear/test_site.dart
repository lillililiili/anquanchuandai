import 'data.dart';

const testSiteId = 'site-1';
const testSiteName = '测试厂区';

/// Narrow the development view without creating a site or changing access grants.
JsonMap testSiteIdentity(JsonMap native) => {
  ...native,
  'siteSelectionLocked': true,
  'sites': [
    for (final site in jsonList(native['sites']))
      if (idOf(site['id']) == testSiteId &&
          site['active'] != false &&
          site['enabled'] != false &&
          (site['status'] == null || idOf(site['status']) == '0'))
        {...site, 'name': testSiteName},
  ],
};
