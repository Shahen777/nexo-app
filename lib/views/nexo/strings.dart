import 'package:fl_clash/common/l10n_labels.dart';
import 'package:fl_clash/enum/enum.dart';

class NexoStrings {
  const NexoStrings._();

  static const appName = 'Nexo';
  static const settings = 'Настройки';
  static const advanced = 'Расширенные';
  static const proxies = 'Серверы и группы';
  static const profiles = 'Ключи доступа';
  static const requests = 'Недавние запросы';
  static const connections = 'Соединения';
  static const dns = 'DNS-запросы';
  static const resources = 'Ресурсы';
  static const logs = 'Журнал';
  static const connect = 'Подключить';
  static const connected = 'Подключено';
  static const connecting = 'Подключаемся…';
  static const protected = 'Соединение защищено';
  static const disconnected = 'Защита выключена';
  static const noAccessKey = 'Нет ключа доступа';
  static const addAccessKey = 'Добавьте ключ доступа';
  static const accessKeyHint = 'Ключ — в веб-кабинете или в Telegram-боте';
  static const pasteLink = 'Вставить ссылку';
  static const scanQr = 'Сканировать QR';
  static const invalidAccessLink = 'В буфере нет подходящей ссылки';
  static const server = 'Сервер';
  static const serversLoading = 'Серверы загружаются…';
  static const chooseServer = 'Выберите сервер';
  static const automatic = 'Автовыбор';
  static const speedTest = 'Проверить скорость';
  static const speedTesting = 'Проверяем скорость…';
  static const unavailable = 'Недоступен';
  static const unlimitedAccess = 'Доступ без срока';

  static String currentServer(String name) => 'Сейчас: $name';

  static String daysLeft(int days) => 'Осталось $days дней';

  static String delay(int milliseconds) => '$milliseconds мс';

  static String speed(String download, String upload) =>
      '↓ $download/с  ↑ $upload/с';
}

extension NexoPageLabel on PageLabel {
  String get nexoLabel =>
      this == PageLabel.tools ? NexoStrings.settings : label;
}
