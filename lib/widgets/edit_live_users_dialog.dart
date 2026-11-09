import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EditLiveUsersCountDialog extends StatefulWidget {
  final FirebaseFirestore db;
  const EditLiveUsersCountDialog({super.key, required this.db});

  @override
  State<EditLiveUsersCountDialog> createState() =>
      _EditLiveUsersCountDialogState();
}

class _EditLiveUsersCountDialogState extends State<EditLiveUsersCountDialog> {
  String _mode = 'auto'; // 'auto' | 'boost' | 'manual'
  final TextEditingController _countCtrl = TextEditingController(text: '0');
  bool _isLoading = true;
  bool _isSaving = false;
  int _currentRealActive = 1;

  @override
  void initState() {
    super.initState();
    _loadCurrentConfig();
  }

  @override
  void dispose() {
    _countCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentConfig() async {
    try {
      final doc = await widget.db
          .collection('market_watch')
          .doc('live_users')
          .get()
          .catchError((_) => widget.db.collection('market_watch').doc('live_users').get());

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final mode = (data['mode'] ?? 'auto').toString();
        final base = data['baseCount']?.toString() ?? '0';
        final count = (data['count'] ?? data['fixedCount'] ?? data['active'] ?? '0').toString();

        setState(() {
          _mode = mode;
          if (_mode == 'boost') {
            _countCtrl.text = base;
          } else if (_mode == 'manual') {
            _countCtrl.text = count;
          } else {
            _countCtrl.text = '0';
          }
        });
      }

      // Check current real presence
      try {
        final snap = await widget.db.collection('live_presence').limit(100).get();
        final now = DateTime.now();
        int active = 0;
        for (final d in snap.docs) {
          final data = d.data();
          final lastSeen = data['lastSeen'];
          DateTime? seenTime;
          if (lastSeen is Timestamp) {
            seenTime = lastSeen.toDate();
          } else if (data['clientTime'] is int) {
            seenTime = DateTime.fromMillisecondsSinceEpoch(data['clientTime']);
          }
          if (seenTime != null &&
              (seenTime.isAfter(now.subtract(const Duration(minutes: 2))) ||
               now.difference(seenTime).abs().inSeconds < 120)) {
            active++;
          }
        }
        if (active < 1) active = 1;
        if (mounted) setState(() => _currentRealActive = active);
      } catch (_) {}
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);
    final int value = int.tryParse(_countCtrl.text.trim()) ?? 0;

    final Map<String, dynamic> payload = {
      'mode': _mode,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (_mode == 'manual') {
      payload['count'] = value;
      payload['fixedCount'] = value;
      payload['active'] = value;
      payload['baseCount'] = 0;
    } else if (_mode == 'boost') {
      payload['baseCount'] = value;
      payload['count'] = _currentRealActive + value;
      payload['fixedCount'] = null;
    } else {
      // Auto mode
      payload['baseCount'] = 0;
      payload['count'] = null;
      payload['fixedCount'] = null;
    }

    try {
      // 1. Save to marketViewDb (activeDb)
      await widget.db
          .collection('market_watch')
          .doc('live_users')
          .set(payload, SetOptions(merge: true));

      // 2. Also mirror to primary FirebaseFirestore
      try {
        if (widget.db != FirebaseFirestore.instance) {
          await FirebaseFirestore.instance
              .collection('market_watch')
              .doc('live_users')
              .set(payload, SetOptions(merge: true));
        }
      } catch (_) {}

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ लाइव यूज़र्स सेटिंग्स सफलतापूर्वक सेव हो गई!'),
          backgroundColor: Color(0xFF0F766E),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ एरर: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.visibility_rounded, color: Color(0xFF38BDF8), size: 24),
          SizedBox(width: 8),
          Text(
            'लाइव काउंट सेटिंग्स',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: _isLoading
          ? const SizedBox(
              height: 120,
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
              ),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2B2B2B),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.people_outline,
                            color: Color(0xFF00E676), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'वर्तमान वास्तविक उपस्थिति: $_currentRealActive यूज़र',
                            style: const TextStyle(
                              color: Color(0xFF00E676),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'काउंट मोड चुनें:',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Option 1: Auto (Real presence)
                  _buildModeOption(
                    title: '1. Auto (100% वास्तविक)',
                    subtitle: 'जितने लोग अभी ऐप में हैं केवल वही दिखेंगे',
                    modeValue: 'auto',
                  ),

                  // Option 2: Boost (Real + Base)
                  _buildModeOption(
                    title: '2. Boost (रियल + बेस जोड़ें)',
                    subtitle: 'वास्तविक यूज़र्स + आपकी संख्या (जैसे Real + 50)',
                    modeValue: 'boost',
                  ),

                  // Option 3: Manual Fixed
                  _buildModeOption(
                    title: '3. Manual (फिक्स संख्या)',
                    subtitle: 'हमेशा वही फिक्स संख्या दिखेगी (जैसे 100)',
                    modeValue: 'manual',
                  ),

                  if (_mode != 'auto') ...[
                    const SizedBox(height: 14),
                    Text(
                      _mode == 'boost'
                          ? 'अतिरिक्त बेस संख्या (Base Boost):'
                          : 'फिक्स संख्या (Fixed Count):',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _countCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF2B2B2B),
                        hintText: _mode == 'boost' ? 'उदा. 50' : 'उदा. 100',
                        hintStyle: const TextStyle(color: Colors.white38),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Presets
                    Wrap(
                      spacing: 8,
                      children: [
                        _buildPresetChip('+10'),
                        _buildPresetChip('+25'),
                        _buildPresetChip('+50'),
                        _buildPresetChip('+100'),
                      ],
                    ),
                  ],
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('रद्द करें', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F766E),
            foregroundColor: Colors.white,
          ),
          onPressed: _isSaving ? null : _saveConfig,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('सेव करें'),
        ),
      ],
    );
  }

  Widget _buildPresetChip(String label) {
    return ActionChip(
      backgroundColor: const Color(0xFF2B2B2B),
      label: Text(
        label,
        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12),
      ),
      onPressed: () {
        final addVal = int.tryParse(label.replaceAll('+', '')) ?? 0;
        final current = int.tryParse(_countCtrl.text.trim()) ?? 0;
        _countCtrl.text = (current + addVal).toString();
      },
    );
  }

  Widget _buildModeOption({
    required String title,
    required String subtitle,
    required String modeValue,
  }) {
    final bool isSelected = _mode == modeValue;
    return InkWell(
      onTap: () => setState(() => _mode = modeValue),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF0F766E).withValues(alpha: 0.2)
              : const Color(0xFF262626),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF0F766E) : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: isSelected ? const Color(0xFF00E676) : Colors.white38,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
