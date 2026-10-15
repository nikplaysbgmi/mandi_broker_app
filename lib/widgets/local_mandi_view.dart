import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class LocalMandiTab extends StatelessWidget {
  const LocalMandiTab({super.key});

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final String day = date.day.toString().padLeft(2, '0');
    final String month = months[date.month - 1];
    return '$day $month ${date.year}';
  }

  String _formatTime(DateTime date) {
    int hour = date.hour;
    final String period = hour >= 12 ? 'PM' : 'AM';
    if (hour > 12) hour -= 12;
    if (hour == 0) hour = 12;
    final String minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('market_watch')
          .doc('local_mandi_summary')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.deepOrange),
          );
        }

        final docData = snapshot.data?.data();
        final Timestamp? timestamp = docData?['updatedAt'] as Timestamp?;
        final List<dynamic> rates =
            (docData != null && docData['rates'] is List)
                ? docData['rates'] as List<dynamic>
                : <dynamic>[];

        final DateTime? updatedAtDate = timestamp?.toDate().toLocal();

        return Column(
          children: [
            // Top Header: Shows exact upload date and time
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF141414),
                border: Border(
                  bottom: BorderSide(color: Color(0xFF262626), width: 1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 15,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        updatedAtDate != null
                            ? _formatDate(updatedAtDate)
                            : _formatDate(DateTime.now()),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: Colors.greenAccent.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircleAvatar(
                          radius: 3.5,
                          backgroundColor: Colors.greenAccent,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          updatedAtDate != null
                              ? 'अपडेट: ${_formatTime(updatedAtDate)}'
                              : 'लाइव भाव',
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Rates List: Displays permanently without dropping after cutoff hours
            Expanded(
              child: rates.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            color: Colors.orange.shade700,
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'कोई मंडी भाव उपलब्ध नहीं है',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'प्रशासन द्वारा भाव दर्ज करने पर यहाँ प्रदर्शित होंगे',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: rates.length,
                      separatorBuilder: (context, index) => const Divider(
                        color: Color(0xFF1F1F1F),
                        height: 1,
                        thickness: 1,
                      ),
                      itemBuilder: (context, index) {
                        final item = rates[index] as Map<String, dynamic>;
                        final String name = item['name']?.toString() ?? '';
                        final String unit =
                            item['unit']?.toString() ?? 'क्विंटल';
                        final num minRate =
                            (item['min'] is num) ? item['min'] as num : 0;
                        final num maxRate =
                            (item['max'] is num) ? item['max'] as num : 0;

                        return Container(
                          color: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      color: Color(0xFF29B6F6),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '($unit)',
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '₹$minRate - ₹$maxRate',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'मंडी भाव',
                                    style: TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
