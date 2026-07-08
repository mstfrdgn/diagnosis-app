import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/backend_manager.dart';

/// Lets the user pick a `.pkcls` Orange model file, loads it on the backend,
/// and – on success – navigates to [InputScreen] with the resulting domain.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _modelPath;
  bool _loading = false;
  String? _error;

  Future<void> _pickModel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pkcls'],
      dialogTitle: 'Select an Orange model file',
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
      _modelPath = path;
    });

    try {
      final domain = await context.read<ApiService>().loadModel(path);
      if (!mounted) return;
      setState(() => _loading = false);
      context.push('/input', extra: domain);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<BackendNotifier>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostic App'),
        centerTitle: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 64, color: Colors.green),
              const SizedBox(height: 16),
              const Text(
                'Backend is running',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'API: ${notifier.baseUrl}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _loading ? null : _pickModel,
                icon: _loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.folder_open),
                label:
                    Text(_loading ? 'Loading model…' : 'Open model (.pkcls)'),
              ),
              if (_modelPath != null && !_loading && _error == null) ...[
                const SizedBox(height: 12),
                Text(
                  _modelPath!,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
