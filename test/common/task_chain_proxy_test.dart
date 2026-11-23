import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

const _chain = ChainProxy(
  enabled: true,
  server: '203.0.113.7',
  port: 1080,
  username: 'user',
  password: 'secret',
);

Map<String, dynamic> _profile() => {
  'proxies': [
    {'name': 'Вена', 'type': 'socks5', 'server': '192.0.2.1', 'port': 1},
  ],
  'proxy-groups': [
    {
      'name': 'Nexo',
      'type': 'select',
      'proxies': ['Вена'],
    },
    {
      'name': 'YouTube',
      'type': 'select',
      'proxies': ['Nexo'],
    },
  ],
  'rules': [
    'DOMAIN-SUFFIX,ya.ru,DIRECT',
    'IP-CIDR,10.0.0.0/8,DIRECT,no-resolve',
    'DOMAIN-SUFFIX,youtube.com,YouTube',
    'IP-CIDR,198.51.100.0/24,Nexo,no-resolve',
    'AND,((NETWORK,UDP),(DST-PORT,443)),REJECT',
    'MATCH,Nexo',
  ],
};

Future<YamlMap> _build(
  Map<String, dynamic> rawConfig,
  ChainProxy? chain,
) async {
  final result = await makeRealProfileTask(
    MakeRealProfileState(
      profilesPath: '/profiles',
      profileId: 1,
      rawConfig: rawConfig,
      realPatchConfig: const PatchClashConfig(),
      overrides: ProfileOverrides(chainProxy: chain),
      appendSystemDns: false,
      proxyGroups: const [],
      rules: const [],
      addedRules: const [],
      defaultUA: 'FlClash-Test',
    ),
  );
  return loadYaml(result.yaml) as YamlMap;
}

void main() {
  group('ChainProxy.tryParse', () {
    test('reads links with a scheme and credentials', () {
      final socks = ChainProxy.tryParse('socks5://us%40r:p:ss@1.2.3.4:1080')!;
      expect(socks.type, ChainProxyType.socks5);
      expect(socks.address, '1.2.3.4:1080');
      expect(socks.username, 'us@r');
      expect(socks.password, 'p:ss');
      expect(socks.enabled, isTrue);

      final http = ChainProxy.tryParse('http://proxy.example.com:3128')!;
      expect(http.type, ChainProxyType.http);
      expect(http.username, isEmpty);
    });

    test('reads the sellers host:port:user:pass and bare forms as SOCKS5', () {
      final seller = ChainProxy.tryParse('1.2.3.4:8000:login:pass')!;
      expect(seller.type, ChainProxyType.socks5);
      expect(seller.address, '1.2.3.4:8000');
      expect(seller.username, 'login');
      expect(seller.password, 'pass');
      expect(ChainProxy.tryParse('login:pass@1.2.3.4:8000')!.username, 'login');
      expect(ChainProxy.tryParse('1.2.3.4:8000')!.port, 8000);
    });

    test('rejects what is not a proxy', () {
      for (final input in [
        '',
        '1.2.3.4',
        '1.2.3.4:0',
        '1.2.3.4:70000',
        'vless://id@1.2.3.4:443',
        'socks5://1.2.3.4:1080/path',
        'two words:1',
      ]) {
        expect(ChainProxy.tryParse(input), isNull, reason: input);
      }
    });

    test('a link survives a round trip', () {
      expect(ChainProxy.tryParse(_chain.link), _chain);
    });
  });

  group('chain proxy in the built profile', () {
    test(
      'dials the chain through Nexo and sends proxied rules to it',
      () async {
        final config = await _build(_profile(), _chain);
        final proxy = (config['proxies'] as YamlList).last as YamlMap;
        expect(proxy['name'], chainProxyName);
        expect(proxy['dialer-proxy'], 'Nexo');
        expect(proxy['username'], 'user');
        expect(proxy['udp'], isTrue);
        expect(config['rules'], [
          'DOMAIN-SUFFIX,ya.ru,DIRECT',
          'IP-CIDR,10.0.0.0/8,DIRECT,no-resolve',
          'DOMAIN-SUFFIX,youtube.com,$chainProxyName',
          'IP-CIDR,198.51.100.0/24,$chainProxyName,no-resolve',
          'AND,((NETWORK,UDP),(DST-PORT,443)),REJECT',
          'MATCH,$chainProxyName',
        ]);
      },
    );

    test('a switched off or missing chain leaves the profile alone', () async {
      for (final chain in [_chain.copyWith(enabled: false), null]) {
        final config = await _build(_profile(), chain);
        expect((config['proxies'] as YamlList).length, 1);
        expect((config['rules'] as YamlList).last, 'MATCH,Nexo');
      }
    });

    test('without an entry to dial through nothing changes', () async {
      final profile = _profile()
        ..['proxy-groups'] = []
        ..['rules'] = ['MATCH,DIRECT'];
      final config = await _build(profile, _chain);
      expect((config['proxies'] as YamlList).length, 1);
      expect(config['rules'], ['MATCH,DIRECT']);
    });
  });
}
