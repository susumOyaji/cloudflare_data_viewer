import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stock Data Viewer',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
      home: const StockListScreen(),
    );
  }
}

class StockListScreen extends StatefulWidget {
  const StockListScreen({super.key});

  @override
  State<StockListScreen> createState() => _StockListScreenState();
}

class _StockListScreenState extends State<StockListScreen> {
  // TODO: デプロイしたCloudflare WorkersのURLに書き換えてください
  final String workerBaseUrl = 'https://preloaded_state.sumitomo0210.workers.dev';

  // 上段に表示するコード
  final List<String> _indicesCodes = ['^DJI', '998407.O', 'USDJPY=FX'];

  // ウォッチリスト（コード、株数、平均取得単価）
  List<Map<String, dynamic>> _watchList = [];

  // デフォルトのウォッチリスト（初回起動時用）
  final List<Map<String, dynamic>> _defaultWatchList = [
    {'code': '7203.T', 'quantity': 100, 'avgPrice': 2000},
    {'code': '5016.T', 'quantity': 0, 'avgPrice': 0},
    {'code': '9984.T', 'quantity': 0, 'avgPrice': 0},
    {'code': '6758.T', 'quantity': 0, 'avgPrice': 0},
    {'code': '8729.T', 'quantity': 0, 'avgPrice': 0},
    {'code': '4755.T', 'quantity': 0, 'avgPrice': 0},
  ];

  List<dynamic> _indicesData = [];
  List<dynamic> _stocksData = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadWatchList();
  }

  // ウォッチリストをローカルストレージから読み込む
  Future<void> _loadWatchList() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString('watchList');

      if (jsonString != null) {
        final List<dynamic> decoded = json.decode(jsonString);
        setState(() {
          _watchList = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      } else {
        // 保存データがない場合はデフォルトを使用
        setState(() {
          _watchList = List.from(_defaultWatchList);
        });
      }
    } catch (e) {
      // エラー時はデフォルトを使用
      setState(() {
        _watchList = List.from(_defaultWatchList);
      });
    }

    // 読み込み完了後にデータを取得
    _fetchData();
  }

  // ウォッチリストをローカルストレージに保存する
  Future<void> _saveWatchList() async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonString = json.encode(_watchList);
    await prefs.setString('watchList', jsonString);
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // APIリクエスト用のコードリストを作成
      final watchListCodes = _watchList.map((e) => e['code'] as String).toList();
      final allCodes = [..._indicesCodes, ...watchListCodes];

      // クエリパラメータを構築
      final queryParameters = {'code': allCodes.join(',')};
      final uri = Uri.parse(workerBaseUrl).replace(queryParameters: queryParameters);

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        try {
          final dynamic decoded = json.decode(utf8.decode(response.bodyBytes));
          // 配列であることを確認
          if (decoded is List) {
            setState(() {
              // データを分類
              _indicesData = decoded.where((item) {
                final code = item['code'] ?? item['data']?['code'];
                return _indicesCodes.contains(code);
              }).toList();

              // ウォッチリストデータにはローカルのポートフォリオ情報をマージ
              _stocksData = decoded
                  .where((item) {
                    final code = item['code'] ?? item['data']?['code'];
                    return !_indicesCodes.contains(code);
                  })
                  .map((item) {
                    final code = (item['code'] ?? item['data']?['code'] ?? '').toString().trim();

                    // ローカル情報を検索してマージ
                    final localInfo = _watchList.firstWhere(
                      (e) => e['code'].toString().trim() == code,
                      orElse: () => {'quantity': 0, 'avgPrice': 0},
                    );

                    // itemは不変かもしれないので新しいMapを作成
                    final newItem = Map<String, dynamic>.from(item);
                    newItem['portfolio'] = localInfo;
                    return newItem;
                  })
                  .toList();

              _isLoading = false;
            });
          } else {
            throw const FormatException('Expected a list of data');
          }
        } catch (e) {
          setState(() {
            _errorMessage = 'Data Parse Error: $e\nResponse might not be JSON.';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Server Error: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection Error: $e';
        _isLoading = false;
      });
    }
  }

  void _deleteStock(String code) {
    setState(() {
      _watchList.removeWhere((item) => item['code'] == code);
      // 表示用データからも削除して即座に反映
      _stocksData.removeWhere((item) {
        final itemCode = item['code'] ?? item['data']?['code'];
        return itemCode == code;
      });
    });
    _saveWatchList(); // 保存
  }

  void _showEditDialog(String currentCode) {
    // 現在の設定値を取得（トリムして比較）
    final currentItem = _watchList.firstWhere(
      (e) => e['code'].toString().trim() == currentCode.trim(),
      orElse: () => {'code': currentCode, 'quantity': 0, 'avgPrice': 0},
    );

    final codeController = TextEditingController(text: currentItem['code'].toString());
    final quantityController = TextEditingController(text: currentItem['quantity'].toString());
    final priceController = TextEditingController(text: currentItem['avgPrice'].toString());

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Stock'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeController,
                decoration: const InputDecoration(labelText: 'Code (e.g. 7203.T)'),
              ),
              TextField(
                controller: quantityController,
                decoration: const InputDecoration(labelText: 'Quantity (e.g. 100)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: priceController,
                decoration: const InputDecoration(labelText: 'Avg Price (e.g. 2000)'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                final newCode = codeController.text.trim();
                final newQuantity = num.tryParse(quantityController.text) ?? 0;
                final newPrice = num.tryParse(priceController.text) ?? 0;

                if (newCode.isNotEmpty) {
                  setState(() {
                    // トリムして比較することで、既存のアイテムを確実に見つける
                    final index = _watchList.indexWhere((e) => e['code'].toString().trim() == currentCode.trim());

                    if (index != -1) {
                      _watchList[index] = {'code': newCode, 'quantity': newQuantity, 'avgPrice': newPrice};
                    }
                    // 見つからない場合は何もしない（増殖バグ防止）
                  });
                  _saveWatchList(); // 保存
                  Navigator.pop(context);
                  _fetchData(); // 新しいコードでデータを再取得
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Data Viewer'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchData)],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _fetchData, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 上段: 主要指標
          const Text('Market Indices', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildIndicesSection(),

          const SizedBox(height: 24),

          // 中段: ポートフォリオ
          const Text('Portfolio', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildPortfolioSection(),

          const SizedBox(height: 24),

          // 下段: 企業カード
          const Text('Watchlist', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildStockCardsSection(),
        ],
      ),
    );
  }

  Widget _buildIndicesSection() {
    if (_indicesData.isEmpty) {
      return const Card(
        child: Padding(padding: EdgeInsets.all(16.0), child: Text('No indices data available')),
      );
    }

    // 3個固定で表示するために最初の3つを取得（データが足りない場合はあるだけ）
    final displayData = _indicesData.take(3).toList();

    return Row(
      children: displayData.map((item) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: SizedBox(
              height: 140, // 高さを固定
              child: _buildStockCard(item, isCompact: true),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPortfolioSection() {
    double totalAsset = 0;
    double totalInvestment = 0;

    for (var item in _stocksData) {
      final data = item['data'] ?? {};
      final priceStr = data['price'] ?? '0';
      final price = double.tryParse(priceStr.replaceAll(',', '')) ?? 0.0;

      final portfolio = item['portfolio'] ?? {};
      final quantity = (portfolio['quantity'] as num?)?.toInt() ?? 0;
      final avgPrice = (portfolio['avgPrice'] as num?)?.toDouble() ?? 0.0;

      if (quantity > 0) {
        totalAsset += price * quantity;
        totalInvestment += avgPrice * quantity;
      }
    }

    final totalGainLoss = totalAsset - totalInvestment;
    double totalGainLossPercent = 0;
    if (totalInvestment > 0) {
      totalGainLossPercent = (totalGainLoss / totalInvestment) * 100;
    }

    final currencyFormat = NumberFormat("#,###");

    Color gainColor = Colors.grey;
    String gainPrefix = '';
    if (totalGainLoss > 0) {
      gainColor = Colors.green;
      gainPrefix = '+';
    } else if (totalGainLoss < 0) {
      gainColor = Colors.red;
    }

    return Card(
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Text('Total Asset Value', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              '¥${currencyFormat.format(totalAsset)}',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (totalGainLoss != 0)
                  Icon(totalGainLoss > 0 ? Icons.arrow_upward : Icons.arrow_downward, color: gainColor, size: 16),
                const SizedBox(width: 4),
                Text(
                  '$gainPrefix¥${currencyFormat.format(totalGainLoss)} ($gainPrefix${totalGainLossPercent.toStringAsFixed(2)}%)',
                  style: TextStyle(color: gainColor, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockCardsSection() {
    if (_stocksData.isEmpty) {
      return const Card(
        child: Padding(padding: EdgeInsets.all(16.0), child: Text('No stock data available')),
      );
    }

    // 表示数を最大5個に制限
    // final int itemCount = _stocksData.length > 5 ? 5 : _stocksData.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 画面幅に応じて列数を決定（最小幅200px程度を想定、最大5列）
        int crossAxisCount = (constraints.maxWidth / 200).floor();
        if (crossAxisCount < 1) crossAxisCount = 1;
        if (crossAxisCount > 5) crossAxisCount = 5;

        return GridView.builder(
          shrinkWrap: true, // 親のスクロールに合わせる
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 1.1, // 高さを確保するために比率を変更
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: _stocksData.length,
          itemBuilder: (context, index) {
            return _buildStockCard(_stocksData[index]);
          },
        );
      },
    );
  }

  Widget _buildStockCard(dynamic item, {bool isCompact = false}) {
    // データ構造に合わせて取得
    final data = item['data'] ?? {};
    final name = data['name'] ?? 'Unknown';
    // item['code'] (リクエスト時のコード、.T付き) を優先して使用する
    final code = item['code'] ?? data['code'] ?? '';
    final priceStr = data['price'] ?? '0';
    final price = double.tryParse(priceStr.replaceAll(',', '')) ?? 0.0;
    final change = data['price_change'] ?? '0';
    final changeRate = data['price_change_rate'] ?? '0.00';

    // ポートフォリオ情報
    final portfolio = item['portfolio'] ?? {};
    final quantity = (portfolio['quantity'] as num?)?.toInt() ?? 0;
    final avgPrice = (portfolio['avgPrice'] as num?)?.toDouble() ?? 0.0;

    // 損益計算
    double gainLoss = 0;
    double gainLossPercent = 0;
    if (quantity > 0) {
      gainLoss = (price - avgPrice) * quantity;
      if (avgPrice > 0) {
        gainLossPercent = ((price - avgPrice) / avgPrice) * 100;
      }
    }

    // 変動値の色判定
    Color changeColor = Colors.grey;
    String prefix = '';
    if (change.toString().startsWith('-')) {
      changeColor = Colors.red;
    } else if (change != '0' && change != '---') {
      changeColor = Colors.green;
      prefix = '+';
    }

    // 損益の色判定
    Color gainColor = Colors.grey;
    String gainPrefix = '';
    if (gainLoss > 0) {
      gainColor = Colors.green;
      gainPrefix = '+';
    } else if (gainLoss < 0) {
      gainColor = Colors.red;
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: isCompact ? const EdgeInsets.all(8.0) : const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(fontSize: isCompact ? 14 : 16, fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        code,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                          fontSize: isCompact ? 10 : 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isCompact)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _showEditDialog(code),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _deleteStock(code),
                      ),
                    ],
                  ),
              ],
            ),

            // ポートフォリオ情報（保有している場合のみ表示）
            if (!isCompact && quantity > 0) ...[
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Qty: $quantity', style: const TextStyle(fontSize: 12)),
                  Text('Avg: ¥$avgPrice', style: const TextStyle(fontSize: 12)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('G/L:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  Text(
                    '$gainPrefix¥${gainLoss.toStringAsFixed(0)} ($gainPrefix${gainLossPercent.toStringAsFixed(2)}%)',
                    style: TextStyle(color: gainColor, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ],
              ),
              const Divider(height: 16),
            ],

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '¥$priceStr',
                  style: TextStyle(fontSize: isCompact ? 16 : 20, fontWeight: FontWeight.bold),
                ),
                if (!isCompact) // コンパクトモードでなければ詳細を表示
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$prefix$change',
                        style: TextStyle(color: changeColor, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      Text(
                        '($prefix$changeRate%)',
                        style: TextStyle(color: changeColor, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
              ],
            ),
            if (isCompact) // コンパクトモードの場合は変動率のみ簡易表示
              Text(
                '$prefix$changeRate%',
                style: TextStyle(color: changeColor, fontWeight: FontWeight.bold, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}
