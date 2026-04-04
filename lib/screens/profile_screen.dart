import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../blocs/profile_cubit.dart';
import '../blocs/shotgun_pattern_cubit.dart';
import '../blocs/subscription_cubit.dart';
import '../models/calibration_record.dart';
import '../models/rifle_profile.dart';
import '../models/shotgun_setup.dart';
import '../models/weapon_profile.dart';
import '../services/shotgun_service.dart';
import 'calibration_result_screen.dart';

/// The two-class pattern:
/// Flutter rebuilds widgets frequently, but state needs to persist across
/// rebuilds. The StatefulWidget is recreated on every rebuild (it's cheap),
/// but the State object is created once and sticks around. This separation
/// lets Flutter be efficient while you keep mutable state safe.

class ProfileScreen extends StatefulWidget {
  final WeaponProfile? editProfile;
  final int? editIndex;
  const ProfileScreen({super.key, this.editProfile, this.editIndex});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  // ── Weapon type ──
  WeaponType _weaponType = WeaponType.rifle;

  // ── Shared ──
  late TextEditingController _name;

  // ── Rifle fields ──
  late TextEditingController _caliber;
  late TextEditingController _barrelLength;
  late TextEditingController _twistRate;
  late TextEditingController _sightHeight;
  late TextEditingController _zeroDistance;
  late TextEditingController _clickValue;
  late TextEditingController _muzzleVelocity;
  late TextEditingController _bulletWeight;
  late TextEditingController _bc;
  DragModel _dragModel = DragModel.g1;

  // ── Shotgun fields ──
  Gauge _gauge = Gauge.g12;
  late TextEditingController _sgBarrelLength;
  ChokeType _chokeType = ChokeType.modified;
  late TextEditingController _loadName;
  ShotCategory _shotCategory = ShotCategory.lead;
  ShotSize _shotSize = ShotSize.s6;
  late TextEditingController _pelletCount;
  late TextEditingController _sgMuzzleVelocity;
  WadType _wadType = WadType.plastic;
  AmmoSpreadClass _ammoSpreadClass = AmmoSpreadClass.standard;
  GameTarget _gameTarget = GameTarget.coyote;

  // ── Calibration state ──
  CalibrationRecord? _calibrationRecord;
  bool _calibrating = false;

  @override
  void initState() {
    super.initState();
    final edit = widget.editProfile;
    if (edit is ShotgunSetup) {
      _loadExistingCalibration(edit.id);
    }

    if (edit is ShotgunSetup) {
      _weaponType = WeaponType.shotgun;
      _name = TextEditingController(text: edit.name);
      _gauge = edit.gauge;
      _sgBarrelLength = TextEditingController(
        text: edit.barrelLengthInches.toString(),
      );
      _chokeType = edit.chokeType;
      _loadName = TextEditingController(text: edit.loadName);
      _shotCategory = edit.shotCategory;
      _shotSize = edit.shotSize;
      _pelletCount = TextEditingController(text: edit.pelletCount.toString());
      _sgMuzzleVelocity = TextEditingController(
        text: edit.muzzleVelocityFps.toString(),
      );
      _wadType = edit.wadType;
      _ammoSpreadClass = edit.ammoSpreadClass;
      _gameTarget = edit.gameTarget;
      // Init rifle controllers to defaults (unused but must exist)
      _initRifleControllers(RifleProfile.default308());
    } else {
      _weaponType = WeaponType.rifle;
      final r = edit as RifleProfile? ?? _defaultRifleFromState();
      _name = TextEditingController(text: r.name);
      _initRifleControllers(r);
      // Init shotgun controllers to defaults (unused but must exist)
      _initShotgunControllers(ShotgunSetup.default12gaMod());
    }
  }

  void _initRifleControllers(RifleProfile p) {
    _caliber = TextEditingController(text: p.caliber);
    _barrelLength = TextEditingController(
      text: p.barrelLengthInches.toString(),
    );
    _twistRate = TextEditingController(text: p.twistRateInches.toString());
    _sightHeight = TextEditingController(text: p.sightHeightInches.toString());
    _zeroDistance = TextEditingController(text: p.zeroDistanceYards.toString());
    _clickValue = TextEditingController(text: p.clickValueMoa.toString());
    _muzzleVelocity = TextEditingController(
      text: p.muzzleVelocityFps.toString(),
    );
    _bulletWeight = TextEditingController(
      text: p.bulletWeightGrains.toString(),
    );
    _bc = TextEditingController(text: p.ballisticCoefficient.toString());
    _dragModel = p.dragModel;
  }

  void _initShotgunControllers(ShotgunSetup s) {
    _sgBarrelLength = TextEditingController(
      text: s.barrelLengthInches.toString(),
    );
    _loadName = TextEditingController(text: s.loadName);
    _pelletCount = TextEditingController(text: s.pelletCount.toString());
    _sgMuzzleVelocity = TextEditingController(
      text: s.muzzleVelocityFps.toString(),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _caliber.dispose();
    _barrelLength.dispose();
    _twistRate.dispose();
    _sightHeight.dispose();
    _zeroDistance.dispose();
    _clickValue.dispose();
    _muzzleVelocity.dispose();
    _bulletWeight.dispose();
    _bc.dispose();
    _sgBarrelLength.dispose();
    _loadName.dispose();
    _pelletCount.dispose();
    _sgMuzzleVelocity.dispose();
    super.dispose();
  }

  RifleProfile _defaultRifleFromState() {
    final state = context.read<ProfileCubit>().state;
    if (state is ProfileLoaded && state.profile is RifleProfile) {
      return state.profile as RifleProfile;
    }
    return RifleProfile.default308();
  }

  Future<void> _loadExistingCalibration(String setupId) async {
    final record = await ShotgunService().loadCalibration(setupId);
    if (mounted && record != null) {
      setState(() => _calibrationRecord = record);
    }
  }

  Future<void> _runCalibration() async {
    final isPro = context.read<SubscriptionCubit>().isPro;
    if (!isPro) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upgrade to Pro to calibrate'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.grey[850],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Calibration Photo',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Fire one shot at a 24"×24" white sheet from 20 yds.\n'
              'Photograph the full sheet with good contrast.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library, size: 18),
                    label: const Text('Photos'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    onPressed: () =>
                        Navigator.of(context).pop(ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: const Text('Take Photo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () =>
                        Navigator.of(context).pop(ImageSource.camera),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final xFile = await picker.pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );
    if (xFile == null || !mounted) return;

    setState(() => _calibrating = true);

    final pelletCount = int.tryParse(_pelletCount.text) ?? 9;
    final setupName = _name.text.trim();
    final cubit = context.read<ShotgunPatternCubit>();

    // Build a temporary setup for analysis
    final setup = ShotgunSetup(
      id: widget.editProfile?.id,
      name: setupName,
      gauge: _gauge,
      barrelLengthInches: double.tryParse(_sgBarrelLength.text) ?? 28,
      chokeType: _chokeType,
      loadName: _loadName.text.trim(),
      shotCategory: _shotCategory,
      shotSize: _shotSize,
      pelletCount: pelletCount,
      muzzleVelocityFps: double.tryParse(_sgMuzzleVelocity.text) ?? 1300,
      wadType: _wadType,
      ammoSpreadClass: _ammoSpreadClass,
      gameTarget: _gameTarget,
    );

    await cubit.analyzePhoto(
      imageFile: File(xFile.path),
      setup: setup,
      distanceYards: 20,
    );

    if (!mounted) return;
    setState(() => _calibrating = false);

    final state = cubit.state;
    if (state is CalibrationReady) {
      final accepted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => BlocProvider.value(
            value: cubit,
            child: CalibrationResultScreen(
              session: state.session,
              before: state.before,
              after: state.after,
              setup: setup,
              distanceYards: 20,
            ),
          ),
        ),
      );
      if (accepted == true && mounted) {
        await _loadExistingCalibration(setup.id);
      }
    } else if (state is CalibrationError) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final WeaponProfile profile;
    if (_weaponType == WeaponType.rifle) {
      profile = RifleProfile(
        id: widget.editProfile?.id,
        name: _name.text.trim(),
        caliber: _caliber.text.trim(),
        barrelLengthInches: double.parse(_barrelLength.text),
        twistRateInches: double.parse(_twistRate.text),
        sightHeightInches: double.parse(_sightHeight.text),
        zeroDistanceYards: double.parse(_zeroDistance.text),
        clickValueMoa: double.parse(_clickValue.text),
        muzzleVelocityFps: double.parse(_muzzleVelocity.text),
        bulletWeightGrains: double.parse(_bulletWeight.text),
        ballisticCoefficient: double.parse(_bc.text),
        dragModel: _dragModel,
      );
    } else {
      profile = ShotgunSetup(
        id: widget.editProfile?.id,
        name: _name.text.trim(),
        gauge: _gauge,
        barrelLengthInches: double.parse(_sgBarrelLength.text),
        chokeType: _chokeType,
        loadName: _loadName.text.trim(),
        shotCategory: _shotCategory,
        shotSize: _shotSize,
        pelletCount: int.parse(_pelletCount.text),
        muzzleVelocityFps: double.parse(_sgMuzzleVelocity.text),
        wadType: _wadType,
        ammoSpreadClass: _ammoSpreadClass,
        gameTarget: _gameTarget,
      );
    }

    final cubit = context.read<ProfileCubit>();
    if (widget.editProfile != null) {
      cubit.save(profile);
    } else {
      cubit.add(profile);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.editProfile != null;
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: Text(
          _weaponType == WeaponType.rifle ? 'Rifle Profile' : 'Shotgun Setup',
        ),
        backgroundColor: Colors.grey[850],
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(
              'SAVE',
              style: TextStyle(color: Colors.orangeAccent),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Weapon type selector — locked when editing
            if (!isEditing) ...[
              Row(
                children: [
                  const Text('Type: ', style: TextStyle(color: Colors.white70)),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Rifle'),
                    selected: _weaponType == WeaponType.rifle,
                    onSelected: (_) =>
                        setState(() => _weaponType = WeaponType.rifle),
                    selectedColor: Colors.orangeAccent,
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Shotgun'),
                    selected: _weaponType == WeaponType.shotgun,
                    onSelected: (_) =>
                        setState(() => _weaponType = WeaponType.shotgun),
                    selectedColor: Colors.orangeAccent,
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            _field('Name', _name),

            if (_weaponType == WeaponType.rifle) ..._rifleFields(),
            if (_weaponType == WeaponType.shotgun) ..._shotgunFields(),
          ],
        ),
      ),
    );
  }

  List<Widget> _rifleFields() {
    return [
      _section('RIFLE'),
      _field('Caliber', _caliber),
      _field('Barrel length (in)', _barrelLength, numeric: true),
      _field('Twist rate (1:X in)', _twistRate, numeric: true),
      _field('Sight height (in)', _sightHeight, numeric: true),
      _field('Zero distance (yds)', _zeroDistance, numeric: true),
      _field('Click value (MOA)', _clickValue, numeric: true),

      const SizedBox(height: 24),
      _section('AMMUNITION'),
      _field('Muzzle velocity (fps)', _muzzleVelocity, numeric: true),
      _field('Bullet weight (gr)', _bulletWeight, numeric: true),
      _field('Ballistic coefficient', _bc, numeric: true),
      const SizedBox(height: 12),
      Row(
        children: [
          const Text('Drag model: ', style: TextStyle(color: Colors.white70)),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('G1'),
            selected: _dragModel == DragModel.g1,
            onSelected: (_) => setState(() => _dragModel = DragModel.g1),
            selectedColor: Colors.orangeAccent,
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('G7'),
            selected: _dragModel == DragModel.g7,
            onSelected: (_) => setState(() => _dragModel = DragModel.g7),
            selectedColor: Colors.orangeAccent,
          ),
        ],
      ),
    ];
  }

  List<Widget> _shotgunFields() {
    return [
      _section('HUNTING'),
      _enumChips<GameTarget>(
        'Game target',
        GameTarget.values,
        _gameTarget,
        (v) => v.label,
        (v) => setState(() => _gameTarget = v),
      ),

      const SizedBox(height: 24),
      _section('GUN'),
      _enumChips<Gauge>(
        'Gauge',
        Gauge.values,
        _gauge,
        (v) => v.label,
        (v) => setState(() {
          _gauge = v;
          _pelletCount.text = ShotgunSetup.estimatePelletCount(
            v,
            _shotSize,
          ).toString();
        }),
      ),
      _field('Barrel length (in)', _sgBarrelLength, numeric: true),

      const SizedBox(height: 24),
      _section('CHOKE'),
      _enumChips<ChokeType>(
        'Choke',
        ChokeType.values,
        _chokeType,
        (v) => v.label,
        (v) => setState(() => _chokeType = v),
      ),

      const SizedBox(height: 24),
      _section('LOAD'),
      _field('Load name', _loadName),
      _enumChips<ShotCategory>(
        'Shot material',
        ShotCategory.values,
        _shotCategory,
        (v) => v.label,
        (v) => setState(() => _shotCategory = v),
      ),
      const SizedBox(height: 12),
      _enumChips<ShotSize>(
        'Shot size',
        ShotSize.values,
        _shotSize,
        (v) => v.label,
        (v) => setState(() {
          _shotSize = v;
          _pelletCount.text = ShotgunSetup.estimatePelletCount(
            _gauge,
            v,
          ).toString();
        }),
      ),
      const SizedBox(height: 12),
      _field('Pellet count', _pelletCount, numeric: true, integer: true),
      _field('Muzzle velocity (fps)', _sgMuzzleVelocity, numeric: true),
      const SizedBox(height: 12),
      _enumChips<WadType>(
        'Wad type',
        WadType.values,
        _wadType,
        (v) => v.label,
        (v) => setState(() => _wadType = v),
      ),
      const SizedBox(height: 12),
      _enumChips<AmmoSpreadClass>(
        'Spread class',
        AmmoSpreadClass.values,
        _ammoSpreadClass,
        (v) => v.label,
        (v) => setState(() => _ammoSpreadClass = v),
      ),

      // ── Calibration ──
      const SizedBox(height: 24),
      _section('CALIBRATION'),
      if (_calibrationRecord != null) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Calibrated',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_calibrationRecord!.sampleCount} sample(s)  ·  '
                      '${(_calibrationRecord!.aggregateConfidence * 100).round()}% confidence',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                  size: 20,
                ),
                tooltip: 'Clear calibration',
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: Colors.grey[900],
                      title: const Text(
                        'Clear calibration?',
                        style: TextStyle(color: Colors.white),
                      ),
                      content: const Text(
                        'Future pattern estimates will use default model values.',
                        style: TextStyle(color: Colors.white70),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text(
                            'Clear',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    final profileId = widget.editProfile?.id ?? '';
                    await ShotgunService().deleteCalibration(profileId);
                    if (mounted) {
                      setState(() => _calibrationRecord = null);
                    }
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      if (_calibrating)
        const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                CircularProgressIndicator(color: Colors.orangeAccent),
                SizedBox(height: 8),
                Text(
                  'Analyzing pattern…',
                  style: TextStyle(color: Colors.white54),
                ),
              ],
            ),
          ),
        )
      else
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.camera_alt, size: 18),
            label: Text(
              _calibrationRecord != null
                  ? 'Re-calibrate from Photo'
                  : 'Calibrate from Photo',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orangeAccent,
              side: const BorderSide(color: Colors.orangeAccent),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _runCalibration,
          ),
        ),
    ];
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.orangeAccent,
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool numeric = false,
    bool integer = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white24),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.orangeAccent),
          ),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) return 'Required';
          if (integer && int.tryParse(value) == null) return 'Invalid integer';
          if (numeric && !integer && double.tryParse(value) == null) {
            return 'Invalid number';
          }
          return null;
        },
      ),
    );
  }

  Widget _enumChips<T>(
    String label,
    List<T> values,
    T selected,
    String Function(T) labelOf,
    ValueChanged<T> onSelected,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: values.map((v) {
            return ChoiceChip(
              label: Text(labelOf(v)),
              selected: v == selected,
              onSelected: (_) => onSelected(v),
              selectedColor: Colors.orangeAccent,
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
