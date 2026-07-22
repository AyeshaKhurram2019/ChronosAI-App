import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:fl_chart/fl_chart.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChronosAIApp());
}

class ChronosAIApp extends StatelessWidget {
  const ChronosAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChronosAI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Colors.deepPurpleAccent,
          secondary: Colors.tealAccent,
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

// ==================== DATABASE HELPER ====================
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('chronos_ai.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            importance INTEGER NOT NULL,
            urgency INTEGER NOT NULL,
            effort INTEGER NOT NULL,
            isCompleted INTEGER NOT NULL,
            createdAt TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE user_stats (
            id INTEGER PRIMARY KEY,
            xp INTEGER NOT NULL,
            level INTEGER NOT NULL,
            streak INTEGER NOT NULL,
            lastActiveDate TEXT
          )
        ''');
        await db.insert('user_stats', {
          'id': 1,
          'xp': 0,
          'level': 1,
          'streak': 1,
          'lastActiveDate': DateTime.now().toIso8601String(),
        });
      },
    );
  }

  Future<int> insertTask(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('tasks', row);
  }

  Future<List<Map<String, dynamic>>> getTasks() async {
    final db = await instance.database;
    return await db.query('tasks');
  }

  Future<int> updateTask(int id, Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.update('tasks', row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteTask(int id) async {
    final db = await instance.database;
    return await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>> getUserStats() async {
    final db = await instance.database;
    final res = await db.query('user_stats', where: 'id = 1');
    return res.first;
  }

  Future<void> addXP(int points) async {
    final db = await instance.database;
    final stats = await getUserStats();
    int currentXP = stats['xp'] + points;
    int currentLevel = stats['level'];

    if (currentXP >= currentLevel * 100) {
      currentLevel += 1;
    }

    await db.update(
      'user_stats',
      {'xp': currentXP, 'level': currentLevel},
      where: 'id = 1',
    );
  }
}

// ==================== MAIN DASHBOARD ====================
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  final List<Widget> _pages = [
    const TaskListTab(),
    const PomodoroTab(),
    const AnalyticsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: Colors.deepPurpleAccent,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.check_circle_outline),
            label: 'Tasks',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.timer_outlined),
            label: 'Pomodoro',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            label: 'Analytics',
          ),
        ],
      ),
    );
  }
}

// ==================== TASK TAB ====================
class TaskListTab extends StatefulWidget {
  const TaskListTab({super.key});

  @override
  State<TaskListTab> createState() => _TaskListTabState();
}

class _TaskListTabState extends State<TaskListTab> {
  List<Map<String, dynamic>> _tasks = [];
  Map<String, dynamic> _userStats = {'xp': 0, 'level': 1, 'streak': 1};
  late stt.SpeechToText _speech;
  bool _isListening = false;
  final TextEditingController _taskController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _refreshData();
  }

  void _refreshData() async {
    final tasks = await DatabaseHelper.instance.getTasks();
    final stats = await DatabaseHelper.instance.getUserStats();

    // AI Priority Sorting Algorithm: (Importance * 3) + (Urgency * 2) - Effort
    List<Map<String, dynamic>> sortedTasks = List.from(tasks);
    sortedTasks.sort((a, b) {
      double scoreA = (a['importance'] * 3) + (a['urgency'] * 2) - (a['effort'] * 1.5);
      double scoreB = (b['importance'] * 3) + (b['urgency'] * 2) - (b['effort'] * 1.5);
      return scoreB.compareTo(scoreA);
    });

    setState(() {
      _tasks = sortedTasks;
      _userStats = stats;
    });
  }

  void _listenVoice() async {
    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) {
            setState(() {
              _taskController.text = val.recognizedWords;
            });
          },
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  void _showAddTaskModal() {
    int importance = 3;
    int urgency = 3;
    int effort = 3;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _taskController,
                      decoration: const InputDecoration(
                        hintText: 'Enter task title...',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(_isListening ? Icons.mic : Icons.mic_none,
                        color: Colors.deepPurpleAccent),
                    onPressed: () {
                      _listenVoice();
                      setModalState(() {});
                    },
                  )
                ],
              ),
              const Divider(),
              Text('Importance: $importance'),
              Slider(
                value: importance.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                onChanged: (v) => setModalState(() => importance = v.toInt()),
              ),
              Text('Urgency: $urgency'),
              Slider(
                value: urgency.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                onChanged: (v) => setModalState(() => urgency = v.toInt()),
              ),
              Text('Effort Required: $effort'),
              Slider(
                value: effort.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                onChanged: (v) => setModalState(() => effort = v.toInt()),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurpleAccent,
                  minimumSize: const Size(double.infinity, 45),
                ),
                onPressed: () async {
                  if (_taskController.text.trim().isNotEmpty) {
                    await DatabaseHelper.instance.insertTask({
                      'title': _taskController.text.trim(),
                      'importance': importance,
                      'urgency': urgency,
                      'effort': effort,
                      'isCompleted': 0,
                      'createdAt': DateTime.now().toIso8601String(),
                    });
                    _taskController.clear();
                    Navigator.pop(context);
                    _refreshData();
                  }
                },
                child: const Text('Add Task', style: TextStyle(color: Colors.white)),
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ChronosAI Workspace'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.local_fire_department, color: Colors.orange),
                Text(' ${_userStats['streak']}d  |  '),
                const Icon(Icons.star, color: Colors.amber),
                Text(' Lvl ${_userStats['level']} (${_userStats['xp']} XP)'),
              ],
            ),
          )
        ],
      ),
      body: _tasks.isEmpty
          ? const Center(child: Text('No tasks found. Add one!'))
          : ListView.builder(
              itemCount: _tasks.length,
              itemBuilder: (context, index) {
                final task = _tasks[index];
                bool isDone = task['isCompleted'] == 1;

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  color: const Color(0xFF1E1E1E),
                  child: ListTile(
                    leading: Checkbox(
                      value: isDone,
                      activeColor: Colors.deepPurpleAccent,
                      onChanged: (bool? value) async {
                        await DatabaseHelper.instance.updateTask(
                          task['id'],
                          {'isCompleted': value == true ? 1 : 0},
                        );
                        if (value == true) {
                          await DatabaseHelper.instance.addXP(10);
                        }
                        _refreshData();
                      },
                    ),
                    title: Text(
                      task['title'],
                      style: TextStyle(
                        decoration: isDone ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    subtitle: Text(
                      'AI Priority Score: ${((task['importance'] * 3) + (task['urgency'] * 2) - (task['effort'] * 1.5)).toStringAsFixed(1)}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () async {
                        await DatabaseHelper.instance.deleteTask(task['id']);
                        _refreshData();
                      },
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.deepPurpleAccent,
        onPressed: _showAddTaskModal,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

// ==================== POMODORO TAB ====================
class PomodoroTab extends StatefulWidget {
  const PomodoroTab({super.key});

  @override
  State<PomodoroTab> createState() => _PomodoroTabState();
}

class _PomodoroTabState extends State<PomodoroTab> {
  static const int focusTime = 25 * 60;
  int _secondsRemaining = focusTime;
  Timer? _timer;
  bool _isRunning = false;

  void _toggleTimer() {
    if (_isRunning) {
      _timer?.cancel();
      setState(() => _isRunning = false);
    } else {
      setState(() => _isRunning = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_secondsRemaining > 0) {
          setState(() => _secondsRemaining--);
        } else {
          _timer?.cancel();
          setState(() {
            _isRunning = false;
            _secondsRemaining = focusTime;
          });
        }
      });
    }
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _secondsRemaining = focusTime;
    });
  }

  String get _timeString {
    int minutes = _secondsRemaining ~/ 60;
    int seconds = _secondsRemaining % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pomodoro Focus')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _timeString,
              style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold, color: Colors.tealAccent),
            ),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
                  onPressed: _toggleTimer,
                  child: Text(_isRunning ? 'Pause' : 'Start', style: const TextStyle(color: Colors.white)),
                ),
                const SizedBox(width: 20),
                OutlinedButton(
                  onPressed: _resetTimer,
                  child: const Text('Reset'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

// ==================== ANALYTICS TAB ====================
class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key});

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  int _completed = 0;
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  void _loadAnalytics() async {
    final tasks = await DatabaseHelper.instance.getTasks();
    int done = tasks.where((t) => t['isCompleted'] == 1).length;
    int active = tasks.length - done;

    setState(() {
      _completed = done;
      _pending = active;
    });
  }

  @override
  Widget build(BuildContext context) {
    int total = _completed + _pending;

    return Scaffold(
      appBar: AppBar(title: const Text('Productivity Analytics')),
      body: total == 0
          ? const Center(child: Text('Add tasks to view analytics metrics.'))
          : Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  const Text('Task Completion Ratio', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 40),
                  SizedBox(
                    height: 200,
                    child: PieChart(
                      PieChartData(
                        sections: [
                          PieChartSectionData(
                            color: Colors.tealAccent,
                            value: _completed.toDouble(),
                            title: 'Done ($_completed)',
                            radius: 50,
                            titleStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                          ),
                          PieChartSectionData(
                            color: Colors.deepPurpleAccent,
                            value: _pending.toDouble(),
                            title: 'Pending ($_pending)',
                            radius: 50,
                            titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

