import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'strings.dart';

class ChainProxyItem extends ConsumerWidget {
  const ChainProxyItem({super.key});

  void _save(WidgetRef ref, int profileId, ChainProxy? chain) {
    ref
        .read(profilesProvider.notifier)
        .updateProfile(
          profileId,
          (profile) => profile.copyWith(
            overrides: profile.overrides.copyWith(chainProxy: chain),
          ),
        );
  }

  Future<void> _edit(WidgetRef ref, int profileId, ChainProxy? chain) async {
    final text = await dialogs.showCommonDialog<String>(
      child: InputDialog(
        title: chain == null
            ? NexoStrings.chainProxy
            : NexoStrings.chainProxyEditTitle,
        value: chain?.link ?? '',
        labelText: NexoStrings.chainProxyLabel,
        hintText: NexoStrings.chainProxyExample,
        inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
        validator: (value) {
          final next = value?.trim() ?? '';
          if (next.isEmpty && chain != null) return null;
          return ChainProxy.tryParse(next) == null
              ? NexoStrings.chainProxyInvalid
              : null;
        },
      ),
    );
    if (text == null) return;
    _save(
      ref,
      profileId,
      text.trim().isEmpty ? null : ChainProxy.tryParse(text),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    if (profile == null) return const SizedBox.shrink();
    final chain = profile.overrides.chainProxy;
    return ListItem(
      leading: const GlyphIcon(AppGlyphs.link),
      title: const Text(NexoStrings.chainProxy),
      subtitle: Text(
        chain?.address ?? NexoStrings.chainProxyHint,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: chain == null
          ? null
          : CommonSwitch(
              value: chain.enabled,
              semanticLabel: NexoStrings.chainProxy,
              onChanged: (value) =>
                  _save(ref, profile.id, chain.copyWith(enabled: value)),
            ),
      onTap: () => _edit(ref, profile.id, chain),
    );
  }
}
