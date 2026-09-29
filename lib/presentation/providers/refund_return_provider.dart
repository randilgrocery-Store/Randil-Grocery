import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/refund_return.dart';
import '../../data/models/sale.dart';
import '../../data/services/supabase_sync_service.dart';

class RefundReturnProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();

  List<RefundReturn> _refunds = [];
  RefundReturn? _selectedRefund;

  List<RefundReturn> get refunds => _refunds;
  List<RefundReturn> get pendingRefunds =>
      _refunds.where((refund) => refund.status == 'Pending').toList();
  RefundReturn? get selectedRefund => _selectedRefund;

  Future<void> loadPendingRefunds() async {
    _refunds = await _dbService.getAllRefunds();
    notifyListeners();
  }

  Future<void> loadRefunds() async {
    _refunds = await _dbService.getAllRefunds();
    notifyListeners();
  }

  Future<void> createRefund({
    required String originalSaleId,
    required List<RefundReturnItem> items,
    required double totalRefundAmount,
    required String refundMethod,
    String invoiceNumber = '',
    String requesterId = '',
    String requesterName = '',
    String notes = '',
  }) async {
    final refund = RefundReturn(
      originalSaleId: originalSaleId,
      invoiceNumber: invoiceNumber,
      items: items,
      totalRefundAmount: totalRefundAmount,
      refundMethod: refundMethod,
      status: 'Pending',
      requesterId: requesterId,
      requesterName: requesterName,
      notes: notes,
    );

    await _dbService.insertRefundReturn(refund);
    await loadRefunds();
    SupabaseSyncService.instance.notifyDataChanged();
  }

  Future<void> approveRefund(String refundId, {String? processedBy}) async {
    final refund = await _dbService.getRefundById(refundId);
    if (refund == null) {
      return;
    }
    final updatedRefund = refund.copyWith(
      status: 'Approved',
      processedBy: processedBy,
      processedDate: DateTime.now(),
    );

    await _dbService.updateRefundReturn(updatedRefund);
    await loadRefunds();
    SupabaseSyncService.instance.notifyDataChanged();
  }

  Future<void> rejectRefund(String refundId, {String? reason}) async {
    final refund = await _dbService.getRefundById(refundId);
    if (refund == null) {
      return;
    }
    final updatedRefund = refund.copyWith(
      status: 'Rejected',
      notes: reason ?? refund.notes,
      processedDate: DateTime.now(),
    );

    await _dbService.updateRefundReturn(updatedRefund);
    await loadRefunds();
    SupabaseSyncService.instance.notifyDataChanged();
  }

  Future<void> processRefund(String refundId) async {
    final refund = await _dbService.getRefundById(refundId);
    if (refund == null) {
      return;
    }

    // Update stock - add refunded items back.
    final originalSale = await _dbService.getSaleById(refund.originalSaleId);
    for (final item in refund.items) {
      // Put the units back into the exact batches they were sold from (oldest
      // first, matching how they were taken) so FIFO pricing stays correct.
      SaleItem? originalLine;
      if (originalSale != null) {
        for (final line in originalSale.items) {
          if (line.id == item.saleItemId ||
              line.productId == item.productId) {
            originalLine = line;
            break;
          }
        }
      }

      if (originalLine != null && originalLine.allocations.isNotEmpty) {
        var remaining = item.quantity;
        for (final allocation in originalLine.allocations) {
          if (remaining <= 0) break;
          final take =
              allocation.quantity < remaining ? allocation.quantity : remaining;
          await _dbService.addBatchQuantity(allocation.batchId, take);
          remaining -= take;
        }
      }

      final product = await _dbService.getProductById(item.productId);
      if (product != null) {
        final updatedProduct = product.copyWith(
          quantity: product.quantity + item.quantity,
        );
        await _dbService.updateProduct(updatedProduct);
        await _dbService.addStockHistory(
          item.productId,
          item.productName,
          item.quantity,
          'Refund: ${refund.id}',
        );
      }
    }

    final updatedRefund = refund.copyWith(
      status: 'Processed',
      processedDate: DateTime.now(),
    );

    await _dbService.updateRefundReturn(updatedRefund);
    await loadRefunds();
    SupabaseSyncService.instance.notifyDataChanged();
  }

  Future<List<RefundReturn>> getRefundsForSale(String saleId) async =>
      _dbService.getRefundsBySale(saleId);

  void selectRefund(RefundReturn? refund) {
    _selectedRefund = refund;
    notifyListeners();
  }
}
