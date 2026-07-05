import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../providers/csv_import_provider.dart';
import '../../data/models/csv_import_model.dart';

class CsvImportScreen extends ConsumerWidget {
  const CsvImportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final importState = ref.watch(csvImportControllerProvider);
    final importResult = ref.watch(csvImportResultProvider);
    final isLoading = importState.isLoading;
    final isDesktop = Responsive.isDesktop(context);

    // Error listen karo
    ref.listen(csvImportControllerProvider, (_, next) {
      if (next.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error.toString()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('CSV Import')),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isDesktop ? 640 : double.infinity,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Template Download Card ──
                _TemplateCard(
                  onDownload: () => _downloadTemplate(context, ref),
                ),
                const SizedBox(height: 20),

                // ── Upload Card ──
                _UploadCard(
                  isLoading: isLoading,
                  onUpload:
                      () =>
                          ref
                              .read(csvImportControllerProvider.notifier)
                              .pickAndImport(),
                ),
                const SizedBox(height: 20),

                // ── Result (agar import hua) ──
                if (importResult != null) ...[
                  _ResultSummaryCard(result: importResult),
                  const SizedBox(height: 16),

                  // Error report (agar koi failed row hai)
                  if (importResult.failedCount > 0) ...[
                    _ErrorReportCard(
                      result: importResult,
                      onDownload:
                          () => _downloadErrorReport(context, importResult),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Template download
  Future<void> _downloadTemplate(BuildContext context, WidgetRef ref) async {
    final csvString =
        ref.read(csvImportControllerProvider.notifier).generateTemplate();

    await _shareFile(
      content: csvString,
      fileName: 'mobileshop_import_template.csv',
      context: context,
    );
  }

  // Error report download
  Future<void> _downloadErrorReport(
    BuildContext context,
    CsvImportResult result,
  ) async {
    // Error report CSV banao
    final lines = StringBuffer();
    lines.writeln('row_number,name,sku,error_reason');

    for (final row in result.failedRows) {
      lines.writeln(
        '${row.rowNumber},'
        '"${row.name ?? ''}",'
        '"${row.sku ?? ''}",'
        '"${row.errorReason ?? ''}"',
      );
    }

    await _shareFile(
      content: lines.toString(),
      fileName: 'import_errors_${DateTime.now().millisecondsSinceEpoch}.csv',
      context: context,
    );
  }

  // File share/download helper
  Future<void> _shareFile({
    required String content,
    required String fileName,
    required BuildContext context,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(content);

    await Share.shareXFiles([XFile(file.path)], subject: fileName);
  }
}

// ════════════════════════════════════════
// WIDGETS
// ════════════════════════════════════════

// Template Download Card
class _TemplateCard extends StatelessWidget {
  final VoidCallback onDownload;

  const _TemplateCard({required this.onDownload});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.download_rounded, color: AppColors.primary),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CSV Template',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'Pehle template download karo, fill karo, phir upload karo',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onDownload, child: const Text('Download')),
        ],
      ),
    );
  }
}

// Upload Card
class _UploadCard extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onUpload;

  const _UploadCard({required this.isLoading, required this.onUpload});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isLoading ? null : onUpload,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.border,
            // Dashed border effect
          ),
        ),
        child: Column(
          children: [
            if (isLoading)
              const CircularProgressIndicator()
            else ...[
              const Icon(
                Icons.upload_file_rounded,
                size: 48,
                color: AppColors.textHint,
              ),
              const SizedBox(height: 12),
              const Text(
                'CSV File Select Karo',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Sirf .csv files allowed hain',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onUpload,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('File Browse Karo'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Result Summary Card
class _ResultSummaryCard extends StatelessWidget {
  final CsvImportResult result;

  const _ResultSummaryCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Import Result',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Total
              _StatChip(
                label: 'Total',
                value: result.totalRows,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              // Success
              _StatChip(
                label: 'Import Hue',
                value: result.successCount,
                color: AppColors.success,
              ),
              const SizedBox(width: 8),
              // Failed
              _StatChip(
                label: 'Reject Hue',
                value: result.failedCount,
                color: AppColors.error,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Error Report Card
class _ErrorReportCard extends StatelessWidget {
  final CsvImportResult result;
  final VoidCallback onDownload;

  const _ErrorReportCard({required this.result, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppColors.error,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Rejected Rows',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.error,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onDownload,
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Download Report'),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Error list
          ...result.failedRows.map(
            (row) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row number badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Row ${row.rowNumber}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Error reason
                  Expanded(
                    child: Text(
                      row.errorReason ?? 'Unknown error',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
