import 'package:flutter/material.dart';

void main() {
  runApp(const InfraExcelApp());
}

class InfraExcelApp extends StatelessWidget {
  const InfraExcelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'حصر وتسعير البنية التحتية',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E7145)), // ثيم الإكسل الأخضر المألوف
        fontFamily: 'Segoe UI',
      ),
      home: const ExcelSheetScreen(),
    );
  }
}

class BOQRowItem {
  final String no;
  final String code;
  final String description;
  final String unit;
  double qty;
  double material;
  double labor;
  double equipment;
  double transport;
  double overheadPct;
  double profitPct;

  BOQRowItem({
    required this.no,
    required this.code,
    required this.description,
    required this.unit,
    required this.qty,
    required this.material,
    required this.labor,
    required this.equipment,
    required this.transport,
    this.overheadPct = 13.0,
    this.profitPct = 15.0,
  });

  double get directCost => material + labor + equipment + transport;
  double get unitRate {
    double costWithOH = directCost * (1 + (overheadPct / 100));
    double profitDivisor = 1.0 - (profitPct / 100);
    return profitDivisor > 0 ? (costWithOH / profitDivisor) : costWithOH;
  }
  double get totalAmount => qty * unitRate;
}

class ExcelSheetScreen extends StatefulWidget {
  const ExcelSheetScreen({super.key});

  @override
  State<ExcelSheetScreen> createState() => _ExcelSheetScreenState();
}

class _ExcelSheetScreenState extends State<ExcelSheetScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // بنود شبكة الصرف الصحي
  final List<BOQRowItem> _sewageItems = [
    BOQRowItem(
      no: '1-1',
      code: 'SEW-UPVC-160',
      description: 'توريد وتركيب مواسير UPVC قطر 160 مم كلاس 4 شامل الحفر حتى عمق 1.70 م والفرشة والردم واختبار الضغط',
      unit: 'م.ط',
      qty: 1250,
      material: 295.0,
      labor: 35.0,
      equipment: 45.0,
      transport: 12.0,
    ),
    BOQRowItem(
      no: '1-2',
      code: 'SEW-UPVC-200',
      description: 'توريد وتركيب مواسير UPVC قطر 200 مم كلاس 4 شامل الحفر والفرشة والردم واختبار الهيدروستاتيك',
      unit: 'م.ط',
      qty: 850,
      material: 380.0,
      labor: 40.0,
      equipment: 55.0,
      transport: 15.0,
    ),
    BOQRowItem(
      no: '1-3',
      code: 'MH-120-RC',
      description: 'إنشاء مطابق صرف صحي دائرية خرسانة مسلحة قطر داخلي 1.20 م بعمق متوسط حتى 2.50 م شامل السلالم والغطاء GRP',
      unit: 'عدد',
      qty: 28,
      material: 12500.0,
      labor: 2800.0,
      equipment: 2200.0,
      transport: 600.0,
    ),
  ];

  // بنود شبكة المياه والحريق
  final List<BOQRowItem> _waterItems = [
    BOQRowItem(
      no: '2-1',
      code: 'WAT-HDPE-110',
      description: 'توريد وتركيب مواسير بولي إيثيلين عالي الكثافة HDPE PE100 قطر 110 مم SDR11 PN16 شامل اللحام البوت فيوجن والحفر',
      unit: 'م.ط',
      qty: 2100,
      material: 310.0,
      labor: 30.0,
      equipment: 40.0,
      transport: 10.0,
    ),
    BOQRowItem(
      no: '2-2',
      code: 'WAT-VLV-100',
      description: 'توريد وتركيب محبس عزل سكينة مرن القفل قطر 100 مم مع غرفة المحبس وغطاء الزهر المرن',
      unit: 'عدد',
      qty: 14,
      material: 8900.0,
      labor: 1200.0,
      equipment: 1500.0,
      transport: 350.0,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  double _calculateTotal(List<BOQRowItem> list) {
    return list.fold(0.0, (sum, item) => sum + item.totalAmount);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('INFRA TRICS — جدول الحصر والتسعير (نظام الإكسل)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF1E7145), // لون ترويسة الإكسل
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.yellowAccent,
          indicatorWeight: 4,
          tabs: const [
            Tab(text: '1. Sewage Network (الصرف)'),
            Tab(text: '2. Water & Fire (المياه والحريق)'),
            Tab(text: '3. Price Bases (الموارد)'),
            Tab(text: '4. Summary (ملخص المشروع)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSpreadsheetTab(_sewageItems, 'شبكة الصرف الصحي'),
          _buildSpreadsheetTab(_waterItems, 'شبكة المياه ومكافحة الحريق'),
          _buildPriceBasesTab(),
          _buildSummaryTab(),
        ],
      ),
    );
  }

  // بناء جدول البيانات المتطابق مع الإكسل
  Widget _buildSpreadsheetTab(List<BOQRowItem> items, String sheetName) {
    double totalSheet = _calculateTotal(items);

    return Column(
      children: [
        // شريط معلومات الشيت والإجمالي
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey[200],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(sheetName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text('إجمالي الشيت: ${totalSheet.toStringAsFixed(2)} ج.م',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E7145), fontSize: 15)),
            ],
          ),
        ),
        // الجدول الإكسل القابل للسحب الأفقي والرأسي
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(const Color(0xFFE8F5E9)),
                border: TableBorder.all(color: Colors.grey.shade300, width: 1),
                columnSpacing: 16,
                columns: const [
                  DataColumn(label: Text('م', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('كود البند', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('بيان الأعمال والمواصفات', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('الوحدة', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('الكمية', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('خامات', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('مصنعيات', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('معدات', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('نقل', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('تكلفة مباشرة', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('فئة السعر (Rate)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                  DataColumn(label: Text('الإجمالي (Amount)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E7145)))),
                ],
                rows: items.map((item) {
                  return DataRow(
                    cells: [
                      DataCell(Text(item.no)),
                      DataCell(Text(item.code, style: const TextStyle(fontWeight: FontWeight.w600))),
                      DataCell(
                        SizedBox(
                          width: 280,
                          child: Text(item.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      DataCell(Text(item.unit)),
                      // خلية الكمية قابلة للتعديل بضغطة زر
                      DataCell(
                        Text('${item.qty}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        showEditIcon: true,
                        onTap: () => _editQuantityDialog(item),
                      ),
                      DataCell(Text('${item.material.toStringAsFixed(1)}')),
                      DataCell(Text('${item.labor.toStringAsFixed(1)}')),
                      DataCell(Text('${item.equipment.toStringAsFixed(1)}')),
                      DataCell(Text('${item.transport.toStringAsFixed(1)}')),
                      DataCell(Text(item.directCost.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w600))),
                      DataCell(Text(item.unitRate.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                      DataCell(Text(item.totalAmount.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E7145)))),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPriceBasesTab() {
    return const Center(child: Text('شيت Price Bases - أسعار الموارد الأساسية وقابلة للتعديل'));
  }

  Widget _buildSummaryTab() {
    double totalSewage = _calculateTotal(_sewageItems);
    double totalWater = _calculateTotal(_waterItems);
    double grandTotal = totalSewage + totalWater;

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ملخص مقايسة المشروع (Project BOQ Summary)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(height: 30),
          ListTile(
            title: const Text('إجمالي شبكة الصرف الصحي'),
            trailing: Text('${totalSewage.toStringAsFixed(2)} ج.م', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ListTile(
            title: const Text('إجمالي شبكة المياه ومكافحة الحريق'),
            trailing: Text('${totalWater.toStringAsFixed(2)} ج.م', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const Divider(),
          ListTile(
            title: const Text('الإجمالي العام للمشروع:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            trailing: Text('${grandTotal.toStringAsFixed(2)} ج.م',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E7145))),
          ),
        ],
      ),
    );
  }

  void _editQuantityDialog(BOQRowItem item) {
    final qtyCtrl = TextEditingController(text: item.qty.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تعديل كمية: ${item.code}'),
        content: TextField(
          controller: qtyCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: 'الكمية المحصورة الجديدة (${item.unit})'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              double? newQty = double.tryParse(qtyCtrl.text);
              if (newQty != null) {
                setState(() => item.qty = newQty);
                Navigator.pop(ctx);
              }
            },
            child: const Text('تحديث الحسابات'),
          ),
        ],
      ),
    );
  }
}
