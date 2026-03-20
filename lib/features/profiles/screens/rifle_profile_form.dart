import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:monyx/../core/theme/app_theme.dart';
import 'package:monyx/features/profiles/models/rifle_profile.dart';
import 'package:monyx/features/profiles/providers/profile_provider.dart';

/// Form for creating or editing a [RifleProfile].
class RifleProfileForm extends ConsumerStatefulWidget {
  const RifleProfileForm({super.key, this.existing});

  /// If non-null, the form will edit this profile; otherwise creates a new one.
  final RifleProfile? existing;

  @override
  ConsumerState<RifleProfileForm> createState() => _RifleProfileFormState();
}

class _RifleProfileFormState extends ConsumerState<RifleProfileForm> {
  final _formKey = GlobalKey<FormState>();

  // ── Controllers ────────────────────────────────────────────────────────────────
  late final TextEditingController _nameCtrl;
  late final TextEditingController _caliberCtrl;
  late final TextEditingController _barrelCtrl;
  late final TextEditingController _twistCtrl;
  late final TextEditingController _zeroDistCtrl;
  late final TextEditingController _sightHeightCtrl;
  late final TextEditingController _clickValueCtrl;

  // Bullet fields
  late final TextEditingController _bulletNameCtrl;
  late final TextEditingController _weightCtrl;
  late final TextEditingController _mvCtrl;
  late final TextEditingController _bcG1Ctrl;
  late final TextEditingController _bcG7Ctrl;
  late final TextEditingController _diamCtrl;

  late OpticUnit _opticUnit;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _caliberCtrl = TextEditingController(text: p?.caliber ?? '');
    _barrelCtrl = TextEditingController(
      text: p?.barrelLengthInches.toString() ?? '24.0',
    );
    _twistCtrl = TextEditingController(
      text: p?.twistRateInchesPerTwist.toString() ?? '10.0',
    );
    _zeroDistCtrl = TextEditingController(
      text: p?.zeroDistanceYards.toString() ?? '100.0',
    );
    _sightHeightCtrl = TextEditingController(
      text: p?.sightHeightInches.toString() ?? '1.5',
    );
    _clickValueCtrl = TextEditingController(
      text: p?.clickValueMoa.toString() ?? '0.25',
    );
    _opticUnit = p?.opticUnit ?? OpticUnit.moa;

    final b = p?.bulletProfile;
    _bulletNameCtrl = TextEditingController(text: b?.bulletName ?? '');
    _weightCtrl = TextEditingController(
      text: b?.bulletWeightGrains.toString() ?? '168.0',
    );
    _mvCtrl = TextEditingController(
      text: b?.muzzleVelocityFps.toString() ?? '2650.0',
    );
    _bcG1Ctrl = TextEditingController(
      text: b?.ballisticCoefficientG1.toString() ?? '0.447',
    );
    _bcG7Ctrl = TextEditingController(
      text: b?.ballisticCoefficientG7?.toString() ?? '',
    );
    _diamCtrl = TextEditingController(
      text: b?.bulletDiameterInches.toString() ?? '0.308',
    );
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _caliberCtrl, _barrelCtrl, _twistCtrl,
      _zeroDistCtrl, _sightHeightCtrl, _clickValueCtrl,
      _bulletNameCtrl, _weightCtrl, _mvCtrl,
      _bcG1Ctrl, _bcG7Ctrl, _diamCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final bullet = BulletProfile(
      bulletName: _bulletNameCtrl.text.trim(),
      bulletWeightGrains: double.parse(_weightCtrl.text),
      muzzleVelocityFps: double.parse(_mvCtrl.text),
      ballisticCoefficientG1: double.parse(_bcG1Ctrl.text),
      ballisticCoefficientG7:
          _bcG7Ctrl.text.trim().isNotEmpty
              ? double.tryParse(_bcG7Ctrl.text)
              : null,
      bulletDiameterInches: double.parse(_diamCtrl.text),
    );

    final notifier = ref.read(rifleProfilesProvider.notifier);

    if (widget.existing != null) {
      final updated = widget.existing!.copyWith(
        name: _nameCtrl.text.trim(),
        caliber: _caliberCtrl.text.trim(),
        barrelLengthInches: double.parse(_barrelCtrl.text),
        twistRateInchesPerTwist: double.parse(_twistCtrl.text),
        zeroDistanceYards: double.parse(_zeroDistCtrl.text),
        sightHeightInches: double.parse(_sightHeightCtrl.text),
        opticUnit: _opticUnit,
        clickValueMoa: double.parse(_clickValueCtrl.text),
        bulletProfile: bullet,
      );
      notifier.updateProfile(updated);
    } else {
      final blank = notifier.createBlank();
      notifier.addProfile(
        blank.copyWith(
          name: _nameCtrl.text.trim(),
          caliber: _caliberCtrl.text.trim(),
          barrelLengthInches: double.parse(_barrelCtrl.text),
          twistRateInchesPerTwist: double.parse(_twistCtrl.text),
          zeroDistanceYards: double.parse(_zeroDistCtrl.text),
          sightHeightInches: double.parse(_sightHeightCtrl.text),
          opticUnit: _opticUnit,
          clickValueMoa: double.parse(_clickValueCtrl.text),
          bulletProfile: bullet,
        ),
      );
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New Profile' : 'Edit Profile'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionHeader('Rifle'),
            _field('Profile Name', _nameCtrl, required: true),
            _field('Caliber', _caliberCtrl, hint: 'e.g. .308 Winchester', required: true),
            _numField('Barrel Length (inches)', _barrelCtrl),
            _numField('Twist Rate (in/turn)', _twistCtrl, hint: 'e.g. 10.0 = 1:10'),
            _numField('Zero Distance (yards)', _zeroDistCtrl),
            _numField('Sight Height (inches)', _sightHeightCtrl),

            const SizedBox(height: 20),
            _sectionHeader('Optic'),
            DropdownButtonFormField<OpticUnit>(
              value: _opticUnit,
              decoration: const InputDecoration(labelText: 'Optic Unit'),
              items: OpticUnit.values
                  .map((u) => DropdownMenuItem(value: u, child: Text(u.displayName)))
                  .toList(),
              onChanged: (v) => setState(() => _opticUnit = v!),
            ),
            const SizedBox(height: 12),
            _numField('Click Value (MOA)', _clickValueCtrl, hint: 'e.g. 0.25 = ¼ MOA'),

            const SizedBox(height: 20),
            _sectionHeader('Bullet / Ammo'),
            _field('Bullet Name', _bulletNameCtrl, hint: 'e.g. Sierra 168gr HPBT'),
            _numField('Bullet Weight (grains)', _weightCtrl),
            _numField('Muzzle Velocity (fps)', _mvCtrl),
            _numField('G1 Ballistic Coefficient', _bcG1Ctrl, hint: 'e.g. 0.447'),
            _numField(
              'G7 Ballistic Coefficient (optional)',
              _bcG7Ctrl,
              hint: 'e.g. 0.223',
              required: false,
            ),
            _numField('Bullet Diameter (inches)', _diamCtrl, hint: 'e.g. 0.308'),

            const SizedBox(height: 32),
            ElevatedButton(onPressed: _save, child: const Text('Save Profile')),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(
      title,
      style: const TextStyle(
        color: AppTheme.primaryOrange,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    ),
  );

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? hint,
    bool required = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: ctrl,
      decoration: InputDecoration(labelText: label, hintText: hint),
      validator:
          required
              ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
              : null,
    ),
  );

  Widget _numField(
    String label,
    TextEditingController ctrl, {
    String? hint,
    bool required = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: ctrl,
      decoration: InputDecoration(labelText: label, hintText: hint),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      validator:
          required
              ? (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (double.tryParse(v) == null) return 'Invalid number';
                return null;
              }
              : (v) {
                if (v != null && v.isNotEmpty && double.tryParse(v) == null) {
                  return 'Invalid number';
                }
                return null;
              },
    ),
  );
}
