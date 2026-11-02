import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/proxies/card.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'strings.dart';

const _accent = Color(0xFF2F6BFF);
const _navy = Color(0xFF0B1F3A);
const _lightPage = Color(0xFFF5F7FB);
const _lightCard = Colors.white;
const _darkCard = Color(0xFF13294A);
const _warning = Color(0xFFF59E0B);
const _contentWidth = 440.0;

Color _pageColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? _navy : _lightPage;

Color _cardColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? _darkCard : _lightCard;

Color _textColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? Colors.white : _navy;

TextStyle _manrope(
  BuildContext context,
  AppTextStyle style, {
  double weight = 400,
  Color? color,
}) {
  return style
      .of(context)
      .copyWith(
        color: color ?? _textColor(context),
        fontFamily: 'Manrope',
        fontVariations: [FontVariation('wght', weight)],
      );
}

class NexoHomeView extends ConsumerWidget {
  const NexoHomeView({super.key});

  String _statusText({
    required bool hasProfile,
    required bool isRunning,
    required CoreStatus coreStatus,
  }) {
    if (!hasProfile) return NexoStrings.noAccessKey;
    if (coreStatus == CoreStatus.connecting) return NexoStrings.connecting;
    return isRunning ? NexoStrings.protected : NexoStrings.disconnected;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    final isRunning = ref.watch(isStartProvider);
    final coreStatus = ref.watch(coreStatusProvider);
    final runtime = ref.watch(runTimeProvider);
    final status = _statusText(
      hasProfile: profile != null,
      isRunning: isRunning,
      coreStatus: coreStatus,
    );
    return CommonScaffold(
      backgroundColor: _pageColor(context),
      titleWidget: Text(
        NexoStrings.appName,
        style: AppTextStyle.pageTitle
            .of(context)
            .copyWith(
              color: _textColor(context),
              fontFamily: 'Unbounded',
              fontVariations: const [FontVariation('wght', 650)],
            ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 72, 20, 24 + context.bottomInset),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  status,
                  textAlign: TextAlign.center,
                  style: _manrope(
                    context,
                    AppTextStyle.subheadline,
                    weight: 500,
                    color: _textColor(context).withValues(alpha: 0.62),
                  ),
                ),
                const SizedBox(height: 28),
                if (profile == null)
                  const _EmptyState()
                else ...[
                  _ConnectButton(
                    isRunning: isRunning,
                    connecting: coreStatus == CoreStatus.connecting,
                    runtime: runtime,
                  ),
                  const SizedBox(height: 28),
                  const _ServerCard(),
                  const SizedBox(height: 16),
                  _InfoRow(profile: profile),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectButton extends ConsumerWidget {
  const _ConnectButton({
    required this.isRunning,
    required this.connecting,
    required this.runtime,
  });

  final bool isRunning;
  final bool connecting;
  final int? runtime;

  void _toggle(WidgetRef ref) {
    if (connecting) return;
    if (system.isAndroid) {
      unawaited(HapticFeedback.mediumImpact());
    }
    ref.read(commonActionProvider.notifier).toggleRunning();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foreground = isRunning ? Colors.white : _textColor(context);
    final fill = isRunning ? _accent : _cardColor(context);
    final label = connecting
        ? NexoStrings.connecting
        : isRunning
        ? NexoStrings.connected
        : NexoStrings.connect;
    return Center(
      child: SizedBox.square(
        dimension: 240,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (connecting)
              const CommonCircleLoading(
                size: 240,
                color: _accent,
                semanticLabel: NexoStrings.connecting,
              ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: SizedBox.square(
                key: ValueKey((isRunning, connecting)),
                dimension: 192,
                child: Material(
                  color: fill,
                  elevation: isRunning ? 12 : 4,
                  shadowColor: _accent.withValues(
                    alpha: isRunning ? 0.34 : 0.1,
                  ),
                  shape: AppShape.circle.copyWith(
                    side: isRunning
                        ? BorderSide.none
                        : const BorderSide(color: _accent, width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    customBorder: AppShape.circle,
                    onTap: connecting ? null : () => _toggle(ref),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          style: _manrope(
                            context,
                            AppTextStyle.headline,
                            weight: 650,
                            color: foreground,
                          ),
                        ),
                        if (isRunning) ...[
                          const SizedBox(height: 8),
                          Text(
                            getTimeText(runtime),
                            style: _manrope(
                              context,
                              AppTextStyle.footnote,
                              weight: 500,
                              color: foreground.withValues(alpha: 0.78),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerCard extends ConsumerWidget {
  const _ServerCard();

  Future<void> _openPicker(BuildContext context) {
    return showFormSheet<void>(
      context: context,
      builder: (_) => const _ServerPicker(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider);
    final group = groups.getGroup(NexoStrings.appName);
    final selected = ref.watch(selectedProxyNameProvider(NexoStrings.appName));
    final selectedName = (selected ?? '').takeFirstValid([
      group?.realNow ?? '',
      NexoStrings.automatic,
    ]);
    final autoNow = groups.getGroup(NexoStrings.automatic)?.realNow ?? '';
    final actual = selectedName == NexoStrings.automatic ? autoNow : '';
    final delay = group == null
        ? null
        : ref.watch(
            delayProvider(proxyName: selectedName, testUrl: group.testUrl),
          );
    return _NexoCard(
      onPressed: group == null ? null : () => _openPicker(context),
      child: Row(
        children: [
          Flexible(child: _ServerMark(name: selectedName)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  NexoStrings.server,
                  style: _manrope(
                    context,
                    AppTextStyle.footnote,
                    weight: 500,
                    color: _textColor(context).withValues(alpha: 0.58),
                  ),
                ),
                const SizedBox(height: 3),
                EmojiText(
                  _serverTitle(selectedName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _manrope(context, AppTextStyle.headline, weight: 650),
                ),
                if (actual.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  EmojiText(
                    actual,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _manrope(
                      context,
                      AppTextStyle.footnote,
                      weight: 500,
                      color: _textColor(context).withValues(alpha: 0.58),
                    ),
                  ),
                ] else if (group == null) ...[
                  const SizedBox(height: 3),
                  Text(
                    NexoStrings.serversLoading,
                    style: _manrope(
                      context,
                      AppTextStyle.footnote,
                      color: _textColor(context).withValues(alpha: 0.58),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _delayText(delay),
            style: _manrope(
              context,
              AppTextStyle.footnote,
              weight: 600,
              color: delay != null && delay < 0
                  ? context.colorScheme.error
                  : _accent,
            ),
          ),
          const SizedBox(width: 6),
          GlyphIcon(
            AppGlyphs.chevronForward,
            size: 18,
            color: _textColor(context).withValues(alpha: 0.42),
          ),
        ],
      ),
    );
  }
}

class _ServerPicker extends ConsumerWidget {
  const _ServerPicker();

  void _select(BuildContext context, WidgetRef ref, Group group, Proxy proxy) {
    selectGroupProxy(
      ref,
      groupName: group.name,
      groupType: group.type,
      proxyName: proxy.name,
    );
    Navigator.of(context).pop();
  }

  void _test(WidgetRef ref, Group group) {
    unawaited(
      ref
          .read(proxiesActionProvider.notifier)
          .delayTestPageGroup(group.name, matchSearch: false),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(
      groupsProvider.select((groups) => groups.getGroup(NexoStrings.appName)),
    );
    final testing = ref.watch(
      delayTestingGroupsProvider.select(
        (groups) => groups.contains(NexoStrings.appName),
      ),
    );
    final selected = ref.watch(proxyNameProvider(NexoStrings.appName));
    final proxies = group == null
        ? const <Proxy>[]
        : [
            ...group.all.where((proxy) => proxy.name == NexoStrings.automatic),
            ...group.all.where((proxy) => proxy.name != NexoStrings.automatic),
          ];
    return CommonScaffold(
      title: NexoStrings.chooseServer,
      backgroundColor: _pageColor(context),
      body: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          for (final proxy in proxies)
            _ServerPickerRow(
              group: group!,
              proxy: proxy,
              selected:
                  (selected ?? '').takeFirstValid([group.realNow]) ==
                  proxy.name,
              onPressed: () => _select(context, ref, group, proxy),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: group == null || testing
                ? null
                : () => _test(ref, group),
            style: const ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(_accent),
              foregroundColor: WidgetStatePropertyAll(Colors.white),
              minimumSize: WidgetStatePropertyAll(Size.fromHeight(48)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (testing)
                  const CommonCircleLoading(
                    size: 18,
                    color: Colors.white,
                    semanticLabel: NexoStrings.speedTesting,
                  )
                else
                  const GlyphIcon(
                    AppGlyphs.speed,
                    size: 20,
                    fill: 1,
                    color: Colors.white,
                  ),
                const SizedBox(width: 8),
                Text(
                  testing ? NexoStrings.speedTesting : NexoStrings.speedTest,
                  style: _manrope(
                    context,
                    AppTextStyle.subheadline,
                    weight: 650,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerPickerRow extends ConsumerWidget {
  const _ServerPickerRow({
    required this.group,
    required this.proxy,
    required this.selected,
    required this.onPressed,
  });

  final Group group;
  final Proxy proxy;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delay = ref.watch(
      delayProvider(proxyName: proxy.name, testUrl: group.testUrl),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: _cardColor(context),
        shape: AppShape.md,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: AppShape.md,
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  _ServerMark(name: proxy.name, size: 38),
                  const SizedBox(width: 12),
                  Expanded(
                    child: EmojiText(
                      _serverTitle(proxy.name),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _manrope(
                        context,
                        AppTextStyle.subheadline,
                        weight: selected ? 650 : 500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _delayText(delay),
                    style: _manrope(
                      context,
                      AppTextStyle.footnote,
                      weight: 600,
                      color: delay != null && delay < 0
                          ? context.colorScheme.error
                          : _accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: SelectionCheck.size,
                    child: selected ? const SelectionCheck() : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends ConsumerWidget {
  const _InfoRow({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expire = profile.subscriptionInfo?.expireDate;
    final seconds = expire?.difference(DateTime.now()).inSeconds;
    final rawDays = seconds == null
        ? null
        : (seconds / Duration.secondsPerDay).ceil();
    final days = rawDays == null || rawDays >= 0 ? rawDays : 0;
    final warning = days != null && days < 3;
    final traffics = ref.watch(trafficsProvider).list;
    final traffic = traffics.isEmpty ? const Traffic() : traffics.last;
    return _NexoCard(
      child: Row(
        children: [
          Expanded(
            child: _InfoValue(
              label: days == null
                  ? NexoStrings.unlimitedAccess
                  : NexoStrings.daysLeft(days),
              color: warning ? _warning : null,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _InfoValue(
              label: NexoStrings.speed(
                traffic.down.shortTraffic.show,
                traffic.up.shortTraffic.show,
              ),
              alignEnd: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoValue extends StatelessWidget {
  const _InfoValue({required this.label, this.color, this.alignEnd = false});

  final String label;
  final Color? color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 2,
      textAlign: alignEnd ? TextAlign.end : TextAlign.start,
      overflow: TextOverflow.ellipsis,
      style: _manrope(
        context,
        AppTextStyle.footnote,
        weight: 600,
        color: color,
      ),
    );
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  String? _accessUrl(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri == null) return null;
    if (uri.scheme == 'https' && uri.host.isNotEmpty) return text;
    if (uri.scheme != 'nexo' || uri.host != 'install-config') return null;
    final nested = uri.queryParameters['url']?.trim();
    final nestedUri = nested == null ? null : Uri.tryParse(nested);
    return nestedUri?.scheme == 'https' && nestedUri?.host.isNotEmpty == true
        ? nested
        : null;
  }

  Future<void> _paste(WidgetRef ref) async {
    final data = await Clipboard.getData('text/plain');
    final url = _accessUrl(data?.text);
    if (url == null) {
      dialogs.showNotifier(
        NexoStrings.invalidAccessLink,
        level: MessageLevel.warning,
      );
      return;
    }
    unawaited(
      ref.read(profilesActionProvider.notifier).addProfileFromLink(url),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _NexoCard(
      child: Column(
        children: [
          const SizedBox.square(
            dimension: 58,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: Color(0x1A2F6BFF),
                shape: AppShape.circle,
              ),
              child: Center(
                child: GlyphIcon(AppGlyphs.profiles, color: _accent, size: 26),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            NexoStrings.addAccessKey,
            textAlign: TextAlign.center,
            style: _manrope(context, AppTextStyle.title3, weight: 650),
          ),
          const SizedBox(height: 8),
          Text(
            NexoStrings.accessKeyHint,
            textAlign: TextAlign.center,
            style: _manrope(
              context,
              AppTextStyle.subheadline,
              color: _textColor(context).withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _paste(ref),
              style: const ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(_accent),
                foregroundColor: WidgetStatePropertyAll(Colors.white),
                minimumSize: WidgetStatePropertyAll(Size.fromHeight(48)),
              ),
              child: Text(
                NexoStrings.pasteLink,
                style: _manrope(
                  context,
                  AppTextStyle.subheadline,
                  weight: 650,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (system.isAndroid) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => unawaited(
                  ref
                      .read(profilesActionProvider.notifier)
                      .addProfileFormQrCode(),
                ),
                style: const ButtonStyle(
                  foregroundColor: WidgetStatePropertyAll(_accent),
                  side: WidgetStatePropertyAll(BorderSide(color: _accent)),
                  minimumSize: WidgetStatePropertyAll(Size.fromHeight(48)),
                ),
                child: Text(
                  NexoStrings.scanQr,
                  style: _manrope(
                    context,
                    AppTextStyle.subheadline,
                    weight: 650,
                    color: _accent,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NexoCard extends StatelessWidget {
  const _NexoCard({required this.child, this.onPressed});

  final Widget child;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: const EdgeInsets.all(18), child: child);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: _cardColor(context),
        shape: AppShape.xl,
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.2
                  : 0.06,
            ),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: AppShape.xl,
        clipBehavior: Clip.antiAlias,
        child: onPressed == null
            ? content
            : InkWell(
                customBorder: AppShape.xl,
                onTap: onPressed,
                child: content,
              ),
      ),
    );
  }
}

class _ServerMark extends StatelessWidget {
  const _ServerMark({required this.name, this.size = 44});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final flag = _serverFlag(name);
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: const ShapeDecoration(
          color: Color(0x142F6BFF),
          shape: AppShape.circle,
        ),
        child: Center(
          child: flag.isEmpty
              ? GlyphIcon(AppGlyphs.bolt, color: _accent, size: size * 0.48)
              : EmojiText(
                  flag,
                  style: AppTextStyle.custom(
                    context,
                    size: size * 0.48,
                    leading: size * 0.58,
                  ),
                ),
        ),
      ),
    );
  }
}

String _serverFlag(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '';
  final token = trimmed.split(RegExp(r'\s+')).first;
  return token.runes.length == 2 ? token : '';
}

String _serverTitle(String name) {
  final flag = _serverFlag(name);
  return flag.isEmpty ? name : name.substring(flag.length).trim();
}

String _delayText(int? delay) {
  if (delay == null || delay == 0) return '—';
  if (delay < 0) return NexoStrings.unavailable;
  return NexoStrings.delay(delay);
}
