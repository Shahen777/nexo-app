# Nexo

## Русский

Nexo — клиентское приложение платного VPN-сервиса Nexo для Android, macOS и Windows.

Проект является форком [FlClash](https://github.com/chen08209/FlClash), распространяется по лицензии
[GPL-3.0](LICENSE), сохраняет уведомления об авторских правах и публикует исходный код в
[Shahen777/nexo-app](https://github.com/Shahen777/nexo-app).

### Сборка

Требования и процесс сборки такие же, как у FlClash: Flutter 3.47.6, Go, Rust и платформенные инструменты.

```bash
git clone --recursive https://github.com/Shahen777/nexo-app.git
cd nexo-app
flutter pub get
dart setup.dart android   # либо windows / macos
```

Подробности по зависимостям платформ смотрите в
[инструкции FlClash](https://github.com/chen08209/FlClash#build-from-source).

### Благодарности

- [FlClash](https://github.com/chen08209/FlClash) — исходное приложение, GPL-3.0.
- [mihomo / Clash.Meta](https://github.com/MetaCubeX/mihomo) — сетевое ядро.
- Авторы и участники обоих проектов, чьи уведомления и лицензии сохранены в репозитории.

## English

Nexo is the client app for the paid Nexo VPN service on Android, macOS, and Windows.

This project is a fork of [FlClash](https://github.com/chen08209/FlClash), is distributed under the
[GPL-3.0 license](LICENSE), retains upstream copyright notices, and publishes its source at
[Shahen777/nexo-app](https://github.com/Shahen777/nexo-app).

### Build

The requirements and build flow are the same as upstream FlClash: Flutter 3.47.6, Go, Rust, and the platform toolchain.

```bash
git clone --recursive https://github.com/Shahen777/nexo-app.git
cd nexo-app
flutter pub get
dart setup.dart android   # or windows / macos
```

See the [FlClash build instructions](https://github.com/chen08209/FlClash#build-from-source) for platform dependencies.

### Credits

- [FlClash](https://github.com/chen08209/FlClash) — upstream application, GPL-3.0.
- [mihomo / Clash.Meta](https://github.com/MetaCubeX/mihomo) — networking core.
- The authors and contributors of both projects; their notices and licenses remain in this repository.
