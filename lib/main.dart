import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تفعيل دعم سطح المكتب (Windows/macOS/Linux)
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const InfraPricingApp());
}

class InfraPricingApp extends StatelessWidget {
  const InfraPricingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'تسعير وحصر البنية التحتية',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F4C81)),
        fontFamily: 'Roboto',
      ),
      home: const DashboardScreen(),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 1. قاعدة البيانات المحلية (Local Database Helper)
// ════════════════════════════════════════════════════════════════════════════

class AppDatabase {
  static final AppDatabase instance = AppDatabase._init();
  static Database? _database;

  AppDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('infra_pricing_master.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    // 1. جدول الموارد والأسعار
    await db.execute('''
      CREATE TABLE resources (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT UNIQUE,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        unit TEXT NOT NULL,
        base_price REAL NOT NULL
      )
    ''');

    // 2. جدول البنود
    await db.execute('''
      CREATE TABLE items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT UNIQUE,
        description TEXT NOT NULL,
        category TEXT NOT NULL,
        unit TEXT NOT NULL
      )
    ''');

    // 3. جدول تفكيك البند (المكونات)
    await db.execute('''
      CREATE TABLE item_components (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER,
        resource_id INTEGER,
        consumption_qty REAL NOT NULL,
        waste_pct REAL DEFAULT 0.0,
        FOREIGN KEY (item_id) REFERENCES items (id) ON DELETE CASCADE,
        FOREIGN KEY (resource_id) REFERENCES resources (id)
      )
    ''');

    // 4. جدول المشاريع
    await db.execute('''
      CREATE TABLE projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        client TEXT,
        site_oh REAL DEFAULT 8.0,
        ho_oh REAL DEFAULT 5.0,
        risk REAL DEFAULT 3.0,
        profit REAL DEFAULT 15.0
      )
    ''');

    // 5. جدول كميات المقايسة
    await db.execute('''
      CREATE TABLE project_boq (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER,
        item_id INTEGER,
        quantity REAL NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects (id) ON DELETE CASCADE,
        FOREIGN KEY (item_id) REFERENCES items (id)
      )
    ''');

    // تغذية أولية بالبيانات للاختبار الفوري
    await _seedInitialData(db);
  }

  Future _seedInitialData(Database db) async {
    // موارد أساسية
    await db.rawInsert('''
      INSERT INTO resources (code, name, category, unit, base_price) VALUES
      ('MAT-UPVC-160', 'مواسير UPVC قطر 160 مم كلاس 4', 'Material', 'm', 280.0),
      ('MAT-SAND', 'رمل تغليف معتمد', 'Material', 'm3', 95.0),
      ('LAB-CREW', 'طاقم تركيب يومي (فني + 2 عمال)', 'Labor', 'day', 1200.0),
      ('EQ-EXC', 'حفار كوماتسو 200 يومية شامل الوقود', 'Equipment', 'day', 4500.0)
    ''');

    // بند قياسي
    final itemId = await db.rawInsert('''
      INSERT INTO items (code, description, category, unit) VALUES
      ('SW-160-01', 'توريد وتركيب مواسير UPVC قطر 160 مم شامل الحفر والفرشة والردم', 'صرف صحي', 'm')
    ''');

    // تفكيك مكونات البند (إنتاجية فرقة 50 متر/يوم)
    await db.rawInsert('''
      INSERT INTO item_components (item_id, resource_id, consumption_qty, waste_pct) VALUES
      ($itemId, 1, 1.00, 3.0),
      ($itemId, 2, 0.40, 5.0),
      ($itemId, 3, 0.02, 0.0),
      ($itemId, 4, 0.02, 0.0)
    ''');

    // مشروع افتراضي
    final prjId = await db.rawInsert('''
      INSERT INTO projects (name, client, site_oh, ho_oh, risk, profit) VALUES
      ('مشروع شبكات منطقة النرجس', 'هيئة المجتمعات العمرانية', 8.0, 5.0, 3.0, 15.0)
    ''');

    // إضافة كمية للبند في المشروع
    await db.rawInsert('''
      INSERT INTO project_boq (project_id, item_id, quantity) VALUES
      ($prjId, $itemId, 1250.0)
    ''');
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 2. المحرك الحسابي الهندسي (Cost Engine)
// ════════════════════════════════════════════════════════════════════════════

class CostEngine {
  static double calculateDirectCost(List<Map<String, dynamic>> components) {
    double total = 0.0;
    for (var comp in components) {
      double basePrice = (comp['base_price'] as num).toDouble();
      double qty = (comp['consumption_qty'] as num).toDouble();
      double waste = (comp['waste_pct'] as num).toDouble();
      total += (qty * (1 + waste / 100)) * basePrice;
    }
    return total;
  }

  static double calculateSellingRate({
    required double directCost,
    required double siteOH,
    required double hoOH,
    required double risk,
    required double profit,
  }) {
    double totalMarkupPct = siteOH + hoOH + risk;
    double costWithOverhead = directCost * (1 + totalMarkupPct / 100);
    double divisor = 1.0 - (profit / 100);
    if (divisor <= 0) return costWithOverhead;
    return costWithOverhead / divisor;
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 3. الشاشة الرئيسية: لوحة القيادة والمشاريع (Dashboard)
// ════════════════════════════════════════════════════════════════════════════

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Map<String, dynamic>> _projects = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    final db = await AppDatabase.instance.database;
    final res = await db.query('projects');
    setState(() {
      _projects = res;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('INFRA TRICS — حصر وتسعير البنية التحتية', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: const Color(0xFF0F4C81),
        foregroundColor: Colors.white,
      ),
      drawer: _buildAppDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _projects.isEmpty
              ? const Center(child: Text('لا توجد مشاريع مضافة حالياً.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _projects.length,
                  itemBuilder: (ctx, i) {
                    final prj = _projects[i];
                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF0F4C81).withValues(alpha: 0.1),
                          child: const Icon(Icons.folder, color: Color(0xFF0F4C81)),
                        ),
                        title: Text(prj['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('الجهة: ${prj['client']} | ربح: ${prj['profit']}%'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProjectBOQScreen(project: prj),
                            ),
                          ).then((_) => _loadProjects());
                        },
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF0F4C81),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('مشروع جديد'),
        onPressed: () => _showAddProjectDialog(),
      ),
    );
  }

  Widget _buildAppDrawer() {
    return Drawer(
      child: ListView(
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Color(0xFF0F4C81)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.architecture, color: Colors.white, size: 40),
                SizedBox(height: 10),
                Text('نظام إدارة التسعير الميداني', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text('قاعدة بيانات غير متصلة (Offline)', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.list_alt),
            title: const Text('مكتبة البنود المركزية'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const MasterItemsScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.attach_money),
            title: const Text('قاعدة أسعار الموارد (Price Bases)'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const PriceBasesScreen()));
            },
          ),
        ],
      ),
    );
  }

  void _showAddProjectDialog() {
    final nameCtrl = TextEditingController();
    final clientCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إنشاء مشروع جديد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم المشروع')),
            TextField(controller: clientCtrl, decoration: const InputDecoration(labelText: 'الجهة المالكة / العميل')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isNotEmpty) {
                final db = await AppDatabase.instance.database;
                await db.insert('projects', {
                  'name': nameCtrl.text,
                  'client': clientCtrl.text,
                  'site_oh': 8.0,
                  'ho_oh': 5.0,
                  'risk': 3.0,
                  'profit': 15.0,
                });
                if (!context.mounted) return;
                Navigator.pop(ctx);
                _loadProjects();
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 4. شاشة مقايسة المشروع والكميات (Project BOQ Screen)
// ════════════════════════════════════════════════════════════════════════════

class ProjectBOQScreen extends StatefulWidget {
  final Map<String, dynamic> project;
  const ProjectBOQScreen({super.key, required this.project});

  @override
  State<ProjectBOQScreen> createState() => _ProjectBOQScreenState();
}

class _ProjectBOQScreenState extends State<ProjectBOQScreen> {
  List<Map<String, dynamic>> _boqItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBOQ();
  }

  Future<void> _loadBOQ() async {
    final db = await AppDatabase.instance.database;
    final res = await db.rawQuery('''
      SELECT 
        pb.id as boq_id,
        pb.quantity,
        i.id as item_id,
        i.code,
        i.description,
        i.unit,
        i.category
      FROM project_boq pb
      JOIN items i ON pb.item_id = i.id
      WHERE pb.project_id = ?
    ''', [widget.project['id']]);

    List<Map<String, dynamic>> calculatedList = [];

    for (var row in res) {
      // جلب مكونات كل بند لحساب تكلفته
      final components = await db.rawQuery('''
        SELECT ic.consumption_qty, ic.waste_pct, r.base_price
        FROM item_components ic
        JOIN resources r ON ic.resource_id = r.id
        WHERE ic.item_id = ?
      ''', [row['item_id']]);

      double directCost = CostEngine.calculateDirectCost(components);
      double sellingRate = CostEngine.calculateSellingRate(
        directCost: directCost,
        siteOH: (widget.project['site_oh'] as num).toDouble(),
        hoOH: (widget.project['ho_oh'] as num).toDouble(),
        risk: (widget.project['risk'] as num).toDouble(),
        profit: (widget.project['profit'] as num).toDouble(),
      );

      double qty = (row['quantity'] as num).toDouble();

      var itemMap = Map<String, dynamic>.from(row);
      itemMap['direct_cost'] = directCost;
      itemMap['selling_rate'] = sellingRate;
      itemMap['total_amount'] = sellingRate * qty;

      calculatedList.add(itemMap);
    }

    setState(() {
      _boqItems = calculatedList;
      _isLoading = false;
    });
  }

  double get _totalProjectAmount {
    return _boqItems.fold(0.0, (sum, i) => sum + (i['total_amount'] as double));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project['name']),
        backgroundColor: const Color(0xFF0F4C81),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: _boqItems.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (ctx, i) {
                      final item = _boqItems[i];
                      return ListTile(
                        title: Text(item['description'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text('كود: ${item['code']} | فئة البند: ${item['selling_rate'].toStringAsFixed(2)} ج.م/${item['unit']}'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${item['total_amount'].toStringAsFixed(0)} ج.م',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 15)),
                            Text('${item['quantity']} ${item['unit']}'),
                          ],
                        ),
                        onTap: () {
                          // فتح تحليل وتفكيك التكلفة للبند
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ItemBreakdownScreen(itemId: item['item_id'], itemDesc: item['description']),
                            ),
                          ).then((_) => _loadBOQ());
                        },
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.blueGrey[50],
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('إجمالي قيمة المقايسة:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('${_totalProjectAmount.toStringAsFixed(2)} ج.م',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F4C81))),
                    ],
                  ),
                )
              ],
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF0F4C81),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
        onPressed: () => _showAddItemToBOQDialog(),
      ),
    );
  }

  void _showAddItemToBOQDialog() async {
    final db = await AppDatabase.instance.database;
    final availableItems = await db.query('items');
    final qtyCtrl = TextEditingController();
    int? selectedItemId = availableItems.isNotEmpty ? availableItems.first['id'] as int : null;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('إضافة بند للمقايسة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<int>(
                isExpanded: true,
                value: selectedItemId,
                items: availableItems
                    .map((it) => DropdownMenuItem<int>(
                          value: it['id'] as int,
                          child: Text(it['description'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedItemId = v),
              ),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'الكمية المحصورة'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (selectedItemId != null && qtyCtrl.text.isNotEmpty) {
                  await db.insert('project_boq', {
                    'project_id': widget.project['id'],
                    'item_id': selectedItemId,
                    'quantity': double.tryParse(qtyCtrl.text) ?? 0.0,
                  });
                  if (!context.mounted) return;
                  Navigator.pop(ctx);
                  _loadBOQ();
                }
              },
              child: const Text('إدراج'),
            )
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 5. شاشة تحليل وتفكيك التكلفة للبند (Item Breakdown Viewer)
// ════════════════════════════════════════════════════════════════════════════

class ItemBreakdownScreen extends StatefulWidget {
  final int itemId;
  final String itemDesc;
  const ItemBreakdownScreen({super.key, required this.itemId, required this.itemDesc});

  @override
  State<ItemBreakdownScreen> createState() => _ItemBreakdownScreenState();
}

class _ItemBreakdownScreenState extends State<ItemBreakdownScreen> {
  List<Map<String, dynamic>> _components = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadComponents();
  }

  Future<void> _loadComponents() async {
    final db = await AppDatabase.instance.database;
    final res = await db.rawQuery('''
      SELECT 
        ic.id,
        r.name as resource_name,
        r.category,
        r.unit,
        r.base_price,
        ic.consumption_qty,
        ic.waste_pct
      FROM item_components ic
      JOIN resources r ON ic.resource_id = r.id
      WHERE ic.item_id = ?
    ''', [widget.itemId]);

    setState(() {
      _components = res;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    double directCost = CostEngine.calculateDirectCost(_components);

    return Scaffold(
      appBar: AppBar(
        title: const Text('تحليل وتفكيك سعر البند'),
        backgroundColor: const Color(0xFF0F4C81),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(widget.itemDesc, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: _components.length,
                    itemBuilder: (ctx, i) {
                      final c = _components[i];
                      double baseP = (c['base_price'] as num).toDouble();
                      double q = (c['consumption_qty'] as num).toDouble();
                      double w = (c['waste_pct'] as num).toDouble();
                      double total = q * (1 + w / 100) * baseP;

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: ListTile(
                          title: Text(c['resource_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('الكمية: $q ${c['unit']} | هالك: $w% | السعر: $baseP ج.م'),
                          trailing: Text('${total.toStringAsFixed(2)} ج.م',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F4C81))),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(20),
                  color: Colors.blueGrey[50],
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('إجمالي التكلفة المباشرة (Direct Cost):', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('${directCost.toStringAsFixed(2)} ج.م',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
                    ],
                  ),
                )
              ],
            ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 6. مكتبة البنود المركزية + إضافة بند جديد (Master Items Screen)
// ════════════════════════════════════════════════════════════════════════════

class MasterItemsScreen extends StatefulWidget {
  const MasterItemsScreen({super.key});

  @override
  State<MasterItemsScreen> createState() => _MasterItemsScreenState();
}

class _MasterItemsScreenState extends State<MasterItemsScreen> {
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final db = await AppDatabase.instance.database;
    final res = await db.query('items');
    setState(() => _items = res);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مكتبة البنود المركزية'),
        backgroundColor: const Color(0xFF0F4C81),
        foregroundColor: Colors.white,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (ctx, i) {
          final it = _items[i];
          return ListTile(
            leading: const Icon(Icons.layers, color: Color(0xFF0F4C81)),
            title: Text(it['description'], style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('كود: ${it['code']} | الوحدة: ${it['unit']} | النوع: ${it['category']}'),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF0F4C81),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('إضافة بند جديد'),
        onPressed: () => _showAddItemDialog(),
      ),
    );
  }

  void _showAddItemDialog() {
    final codeCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String category = 'صرف صحي';
    String unit = 'm';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          title: const Text('إضافة بند جديد للمكتبة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'كود البند (مثال: SEW-200)')),
                TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'التوصيف الفني للبند')),
                DropdownButton<String>(
                  isExpanded: true,
                  value: category,
                  items: ['صرف صحي', 'مياه شرب', 'حريق', 'ري', 'صرف مطر', 'غرف ومحابس']
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setDState(() => category = v!),
                ),
                DropdownButton<String>(
                  isExpanded: true,
                  value: unit,
                  items: ['m', 'm3', 'No', 'ton', 'item']
                      .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                      .toList(),
                  onChanged: (v) => setDState(() => unit = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (codeCtrl.text.isNotEmpty && descCtrl.text.isNotEmpty) {
                  final db = await AppDatabase.instance.database;
                  await db.insert('items', {
                    'code': codeCtrl.text,
                    'description': descCtrl.text,
                    'category': category,
                    'unit': unit,
                  });
                  if (!context.mounted) return;
                  Navigator.pop(ctx);
                  _loadItems();
                }
              },
              child: const Text('إضافة'),
            )
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 7. شاشة أسعار الموارد الأساسية (Price Bases Manager)
// ════════════════════════════════════════════════════════════════════════════

class PriceBasesScreen extends StatefulWidget {
  const PriceBasesScreen({super.key});

  @override
  State<PriceBasesScreen> createState() => _PriceBasesScreenState();
}

class _PriceBasesScreenState extends State<PriceBasesScreen> {
  List<Map<String, dynamic>> _resources = [];

  @override
  void initState() {
    super.initState();
    _loadResources();
  }

  Future<void> _loadResources() async {
    final db = await AppDatabase.instance.database;
    final res = await db.query('resources');
    setState(() => _resources = res);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('قاعدة أسعار الموارد (Price Bases)'),
        backgroundColor: const Color(0xFF0F4C81),
        foregroundColor: Colors.white,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: _resources.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (ctx, i) {
          final res = _resources[i];
          return ListTile(
            title: Text(res['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('التصنيف: ${res['category']} | الوحدة: ${res['unit']}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${res['base_price']} ج.م', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20, color: Colors.blue),
                  onPressed: () => _showEditPriceDialog(res),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showEditPriceDialog(Map<String, dynamic> res) {
    final priceCtrl = TextEditingController(text: res['base_price'].toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تعديل سعر: ${res['name']}'),
        content: TextField(
          controller: priceCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'السعر الأساسي الجديد'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              double? newP = double.tryParse(priceCtrl.text);
              if (newP != null) {
                final db = await AppDatabase.instance.database;
                await db.update(
                  'resources',
                  {'base_price': newP},
                  where: 'id = ?',
                  whereArgs: [res['id']],
                );
                if (!context.mounted) return;
                Navigator.pop(ctx);
                _loadResources();
              }
            },
            child: const Text('تحديث'),
          ),
        ],
      ),
    );
  }
}
