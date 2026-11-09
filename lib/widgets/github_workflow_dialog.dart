import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../services/mandi_services.dart';

class GitHubWorkflowDialog extends StatefulWidget {
  const GitHubWorkflowDialog({super.key});

  @override
  State<GitHubWorkflowDialog> createState() => _GitHubWorkflowDialogState();
}

class _GitHubWorkflowDialogState extends State<GitHubWorkflowDialog> {
  static const String _repoOwner = 'nikplaysbgmi';
  static const String _repoName = 'mandi_broker_app';
  static const String _workflowFile = 'ncdex_sync.yml';
  static const String _workflowUrl =
      'https://github.com/$_repoOwner/$_repoName/actions/workflows/$_workflowFile';

  final _tokenCtrl = TextEditingController();
  bool _isTriggering = false;
  bool _showTokenInput = false;
  String? _savedToken;

  @override
  void initState() {
    super.initState();
    _savedToken = StorageService.get('github_pat_token');
    if (_savedToken != null && _savedToken!.isNotEmpty) {
      _tokenCtrl.text = _savedToken!;
    }
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _openGitHubInBrowser() async {
    try {
      final uri = Uri.parse(_workflowUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open browser.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error launching URL: $e')),
        );
      }
    }
  }

  Future<void> _triggerWorkflow() async {
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty) {
      setState(() => _showTokenInput = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('कृपया GitHub Personal Access Token (PAT) दर्ज करें।'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    setState(() => _isTriggering = true);

    try {
      // Save token for future 1-click use
      StorageService.save('github_pat_token', token);
      _savedToken = token;

      final url = Uri.parse(
          'https://api.github.com/repos/$_repoOwner/$_repoName/actions/workflows/$_workflowFile/dispatches');

      final response = await http.post(
        url,
        headers: {
          'Accept': 'application/vnd.github+json',
          'Authorization': 'Bearer $token',
          'X-GitHub-Api-Version': '2022-11-28',
        },
        body: jsonEncode({'ref': 'main'}),
      );

      if (!mounted) return;
      setState(() => _isTriggering = false);

      if (response.statusCode == 204) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '🚀 NCDEX Sync Workflow सफलतापूर्वक ट्रिगर हो गया! 1-2 मिनट में भाव अपडेट हो जाएंगे।'),
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 4),
          ),
        );
      } else {
        String errMsg = 'Status: ${response.statusCode}';
        try {
          final resJson = jsonDecode(response.body);
          if (resJson['message'] != null) {
            errMsg = resJson['message'];
          }
        } catch (_) {}

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GitHub Error: $errMsg'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isTriggering = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Workflow trigger error: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.play_circle_fill_rounded,
                      color: Color(0xFF38BDF8),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GitHub Workflow Runner',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'NCDEX Live Scrape & Bhav Sync',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white60),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: Color(0xFF334155), height: 1),
              const SizedBox(height: 14),

              // Info Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF16253B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.schedule_rounded,
                            size: 15, color: Color(0xFF10B981)),
                        SizedBox(width: 6),
                        Text(
                          'ऑटोमैटिक 3-मिनट लाइव लूप (Continuous Loop):',
                          style: TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      '• यह वर्कफ़्लो शुरू होते ही लगातार ~25 मिनट तक बैकग्राउंड में चलता है और हर 3 मिनट में अपने-आप ताज़ा NCDEX भाव सिंक करता रहता है!\n• सोमवार से शुक्रवार (9:30 AM - 5:30 PM IST) यह चक्र लगातार अपने-आप दोहराया जाता है।',
                      style: TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Button 1: Open in GitHub Browser (No setup needed)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: const Color(0xFF38BDF8),
                  side: const BorderSide(color: Color(0xFF0284C7), width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _openGitHubInBrowser,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text(
                  '🌐 Open GitHub Actions in Browser',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'ब्राउज़र में खोलकर सीधे "Run workflow" बटन दबाएं',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 10.5),
                ),
              ),

              const SizedBox(height: 10),
              const Row(
                children: [
                  Expanded(child: Divider(color: Color(0xFF334155))),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('या सीधे ऐप से चलाएं',
                        style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ),
                  Expanded(child: Divider(color: Color(0xFF334155))),
                ],
              ),
              const SizedBox(height: 10),

              // Button 2: Direct In-App API Trigger
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _isTriggering ? null : _triggerWorkflow,
                icon: _isTriggering
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.bolt_rounded, size: 20),
                label: Text(
                  _isTriggering
                      ? 'वर्कफ़्लो ट्रिगर हो रहा है...'
                      : '⚡ 1-Click Run Workflow (ऐप से चलाएं)',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),

              // Optional Token Input toggle
              if (!_showTokenInput && (_savedToken == null || _savedToken!.isEmpty))
                TextButton(
                  onPressed: () => setState(() => _showTokenInput = true),
                  child: const Text(
                    '🔑 GitHub Personal Access Token सेट करें',
                    style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11.5),
                  ),
                ),

              if (_showTokenInput || (_savedToken != null && _savedToken!.isNotEmpty)) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _tokenCtrl,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'GitHub Token (ghp_...)',
                    labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                    hintText: 'ghp_xxxxxxxxxxxx',
                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 11),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF334155)),
                    ),
                    suffixIcon: _savedToken != null && _savedToken!.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline,
                                size: 16, color: Colors.redAccent),
                            tooltip: 'Clear Token',
                            onPressed: () {
                              StorageService.remove('github_pat_token');
                              _tokenCtrl.clear();
                              setState(() => _savedToken = null);
                            },
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'GitHub Settings > Developer Settings > Personal Access Tokens (Classic) में workflow परमिशन वाला टोकन',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 10),
                ),
              ],

              const SizedBox(height: 14),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('बंद करें (Close)',
                    style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
