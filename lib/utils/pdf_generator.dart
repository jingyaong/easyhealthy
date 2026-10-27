import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PdfGenerator {
  static Future<Uint8List> generateActivityPdf({
    required int? year,
    required int? month,
    required Map<DateTime, List<Map<String, dynamic>>> groupedActivities,
    required int totalCalories,
    required int avgCalories,
    required int highestCalories,
    required int totalActiveDays,
    required int highestHabitStreak,
    required int totalHabitStreaks,
    required Map<String, double> activityBreakdown,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.openSansRegular();
    final boldFont = await PdfGoogleFonts.openSansBold();

    final logoImage = pw.MemoryImage(
      (await rootBundle.load('assets/EasyHealthyLogo.png')).buffer.asUint8List(),
    );

    // Report title
    String titleText;
    if (year == null) {
      titleText = 'Summary Report';
    } else if (month == null) {
      titleText = 'Summary Report for $year';
    } else {
      final monthName = DateFormat('MMMM').format(DateTime(0, month));
      titleText = 'Summary Report for $monthName $year';
    }

    final List<pw.Widget> content = [];

    // Logo
    content.add(
      pw.Container(
        alignment: pw.Alignment.center,
        margin: const pw.EdgeInsets.only(bottom: 20),
        child: pw.Image(logoImage, width: 120),
      ),
    );

    // MAIN TITLE
    content.add(
      pw.Header(
        level: 0,
        child: pw.Align(
          alignment: pw.Alignment.center,
          child: pw.Text(
            titleText,
            style: pw.TextStyle(font: boldFont, fontSize: 24),
          ),
        ),
      ),
    );

    content.add(pw.SizedBox(height: 20));


    // FITNESS SUMMARY
    content.add(
      pw.Header(
        level: 1,
        child: pw.Text(
          'Fitness Summary',
          style: pw.TextStyle(font: boldFont, fontSize: 18),
        ),
      ),
    );

    content.add(pw.SizedBox(height: 10));

    content.add(
      pw.Center(
        child: pw.Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _buildMetricCard('Total Calories Burned', '${totalCalories}kcal', font, boldFont),
            _buildMetricCard('Avg Calories/Day', '${avgCalories}kcal', font, boldFont),
            _buildMetricCard('Highest Day Calories', '${highestCalories}kcal', font, boldFont),
            _buildMetricCard('Total Active Days', '$totalActiveDays', font, boldFont),
            _buildMetricCard('Highest Habit Streak', '$highestHabitStreak days', font, boldFont),
            _buildMetricCard('Total Habit Streaks', '$totalHabitStreaks', font, boldFont),
          ],
        ),
      ),
    );

    content.add(
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 20, bottom: 10),
        child: pw.Divider(),
      ),
    );


    // ACTIVITY BREAKDOWN
    content.add(
      pw.Header(
        level: 1,
        child: pw.Text(
          'Activity Breakdown',
          style: pw.TextStyle(font: boldFont, fontSize: 18),
        ),
      ),
    );

    content.add(pw.SizedBox(height: 10));

    if (activityBreakdown.isEmpty) {
      content.add(
        pw.Text(
          'No activity data to display breakdown.',
          style: pw.TextStyle(font: font, fontStyle: pw.FontStyle.italic),
        ),
      );
    } else {
      final double totalActivities =
      activityBreakdown.values.fold(0, (sum, count) => sum + count);

      final breakdownWidgets = activityBreakdown.entries.map((entry) {
        final double percentage = totalActivities > 0
            ? (entry.value / totalActivities) * 100
            : 0;

        return pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Row(
            children: [
              // Display the activity name and its raw count
              pw.Text(
                '${entry.key} (${entry.value.toInt()} ${entry.value == 1 ? "activity" : "activities"})',
                style: pw.TextStyle(font: font, fontSize: 14),
              ),
              pw.Expanded(
                child: pw.Container(
                  margin: const pw.EdgeInsets.symmetric(horizontal: 8),
                  child: pw.Divider(
                    borderStyle: pw.BorderStyle.dotted,
                    color: PdfColors.grey,
                    height: 1,
                  ),
                ),
              ),
              pw.Text(
                '${percentage.toStringAsFixed(1)}%',
                style: pw.TextStyle(
                    font: boldFont, fontSize: 14, color: PdfColors.blueGrey),
              ),
            ],
          ),
        );
      }).toList();

      breakdownWidgets.add(
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Container(),
              ),
              pw.Text(
                'Total (${totalActivities.toInt()} ${totalActivities == 1 ? "activity" : "activities"})',
                style: pw.TextStyle(font: boldFont, fontSize: 14),
              ),
            ],
          ),
        ),
      );

      content.add(pw.Column(children: breakdownWidgets));
    }

    content.add(pw.NewPage());

    // ACTIVITY HISTORY
    content.add(
      pw.Header(
        level: 1,
        child: pw.Text(
          'Activity History',
          style: pw.TextStyle(font: boldFont, fontSize: 18),
        ),
      ),
    );

    content.add(pw.Divider(thickness: 1, height: 15));

    if (groupedActivities.isEmpty) {
      content.add(
        pw.Center(
          child: pw.Padding(
            padding: const pw.EdgeInsets.all(40),
            child: pw.Text(
              'No activities found for the selected period.',
              style: pw.TextStyle(font: font, fontStyle: pw.FontStyle.italic),
            ),
          ),
        ),
      );
    } else {
      final sortedDates =
      groupedActivities.keys.toList()..sort((a, b) => b.compareTo(a));

      for (final date in sortedDates) {
        final activitiesOnDate = groupedActivities[date]!;

        content.add(
          pw.Wrap(
            alignment: pw.WrapAlignment.start,
            runSpacing: 10,
            children: [
              pw.Text(
                DateFormat.yMMMMEEEEd().format(date),
                style: pw.TextStyle(font: boldFont, fontSize: 16),
              ),
              pw.Divider(height: 5),
              pw.SizedBox(height: 5),
              pw.Table(
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1),
                },
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 1),
                children: activitiesOnDate.map((activity) {
                  return pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          activity['activityName'],
                          style: pw.TextStyle(font: font),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          activity['displayStatus'],
                          style: pw.TextStyle(
                            font: boldFont,
                            color: _getStatusColor(activity['displayStatus']),
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
              pw.SizedBox(height: 20),
            ],
          ),
        );
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => content,
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(font: font, color: PdfColors.grey),
          ),
        ),
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildMetricCard(
      String title, String value, pw.Font font, pw.Font boldFont) {
    return pw.Container(
      width: 250,
      height: 80,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            value,
            style:
            pw.TextStyle(font: boldFont, fontSize: 18, color: PdfColors.orange),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            title,
            style: pw.TextStyle(font: font, fontSize: 10),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );
  }

  static PdfColor _getStatusColor(String status) {
    switch (status) {
      case 'Completed':
        return PdfColors.green;
      case 'Missed':
        return PdfColors.red;
      default:
        return PdfColors.grey;
    }
  }
}
