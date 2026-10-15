import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../main.dart'; // Uses marketViewDb

class EditPromoDialog extends StatefulWidget {
  const EditPromoDialog({super.key});

  @override
  State<EditPromoDialog> createState() => _EditPromoDialogState();
}

class _EditPromoDialogState extends State<EditPromoDialog> {
  final _urlCtrl = TextEditingController();
  bool _isActive = true;
  bool _isSaving = false;
  bool _isUploading = false;

  // Replace with your free key from https://api.imgbb.com/
  static const String _imgBbApiKey = "e7eaf830df6f232fa61240e72675076f";

  @override
  void initState() {
    super.initState();
    _loadPromoData();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPromoData() async {
    try {
      final doc = await marketViewDb
          .collection('market_watch')
          .doc('promo_config')
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        _urlCtrl.text = data['imageUrl']?.toString() ?? '';
        setState(() {
          _isActive = data['isActive'] ?? true;
        });
      }
    } catch (e) {
      debugPrint('Error loading promo settings: $e');
    }
  }

  // Uploads directly to ImgBB and receives permanent image link
  Future<void> _pickAndUploadToImgBB() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (file == null) return;

    setState(() => _isUploading = true);

    try {
      final Uint8List bytes = await file.readAsBytes();
      final String base64Image = base64Encode(bytes);

      final uri = Uri.parse('https://api.imgbb.com/1/upload?key=$_imgBbApiKey');
      final response = await http.post(
        uri,
        body: {
          'image': base64Image,
          'name': 'promo_${DateTime.now().millisecondsSinceEpoch}',
        },
      );

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        // direct display URL
        final String uploadedUrl =
            data['data']['display_url'] ?? data['data']['url'];

        setState(() {
          _urlCtrl.text = uploadedUrl;
          _isUploading = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Poster uploaded successfully via ImgBB!'),
              backgroundColor: Color(0xFF0F766E),
            ),
          );
        }
      } else {
        throw Exception(data['error']?['message'] ?? 'Upload failed');
      }
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ImgBB Upload Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _savePromo() async {
    setState(() => _isSaving = true);
    try {
      await marketViewDb.collection('market_watch').doc('promo_config').set({
        'imageUrl': _urlCtrl.text.trim(),
        'isActive': _isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() => _isSaving = false);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving promo: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text(
        'प्रमोशन / पोस्टर सेटिंग्स (ImgBB API)',
        style: TextStyle(color: Colors.white, fontSize: 18),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2B2B2B),
                foregroundColor: const Color(0xFF29B6F6),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _isUploading ? null : _pickAndUploadToImgBB,
              icon: _isUploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload),
              label: Text(_isUploading
                  ? 'Uploading to ImgBB...'
                  : 'Upload Image from Gallery'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Direct Poster URL',
                labelStyle: TextStyle(color: Colors.white70),
                border: OutlineInputBorder(),
                hintText: 'https://i.ibb.co/...',
                hintStyle: TextStyle(color: Colors.white38),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Show Poster on App Start',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              value: _isActive,
              onChanged: (val) => setState(() => _isActive = val),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('रद्द करें', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _savePromo,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF5722),
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('सेव करें', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
