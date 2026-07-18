import 'package:all_observer/all_observer.dart';
import 'package:all_observer_devtools/all_observer_devtools.dart';
import 'package:flutter/material.dart';

/// Demo app for `all_observer_devtools`. Run it, open Flutter DevTools,
/// go to the Extensions tab, select "all_observer", and use the controls
/// below to generate real Observer Protocol traffic — node create/update/
/// dispose, dependency edges, scope create/dispose, and a worker/async
/// flow — so every screen of the extension panel has something to show.
///
/// `AllObserverDevTools.initialize()` is gated by `assert()`, exactly as
/// the root package's README recommends: a no-op in release builds, with
/// zero cost beyond the guard.
void main() {
  assert(() {
    AllObserverDevTools.initialize();
    return true;
  }());
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'all_observer_devtools example',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final CounterController _counter = CounterController();
  final TaskListController _tasks = TaskListController();
  final SearchController _search = SearchController();
  final AsyncProfileController _profile = AsyncProfileController();
  final DynamicCountersController _dynamic = DynamicCountersController();

  @override
  void dispose() {
    _counter.dispose();
    _tasks.dispose();
    _search.dispose();
    _profile.dispose();
    _dynamic.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('all_observer_devtools example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'Counter — Observable + Computed',
            child: _CounterDemo(controller: _counter),
          ),
          _Section(
            title: 'Task list — reactive collection',
            child: _TaskListDemo(controller: _tasks),
          ),
          _Section(
            title: 'Search — debounce worker',
            child: _SearchDemo(controller: _search),
          ),
          _Section(
            title: 'Profile — ObservableFuture (loading/data/error)',
            child: _ProfileDemo(controller: _profile),
          ),
          _Section(
            title: 'Dynamic counters — runtime node/scope create + dispose',
            child: _DynamicCountersDemo(controller: _dynamic),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. Counter — the canonical Observable + Computed example.
// ---------------------------------------------------------------------------

class CounterController with ScopedObserverMixin {
  final count = 0.obs;

  late final Computed<int> doubled = scoped(() => Computed(() => count.value * 2));

  void increment() => count.value++;
  void reset() => count.value = 0;

  void dispose() {
    count.close();
    disposeScope();
  }
}

class _CounterDemo extends StatelessWidget {
  const _CounterDemo({required this.controller});

  final CounterController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Observer(() => Text('Count: ${controller.count.value}')),
        const SizedBox(width: 16),
        Observer(() => Text('Doubled: ${controller.doubled.value}')),
        const Spacer(),
        OutlinedButton(onPressed: controller.reset, child: const Text('Reset')),
        const SizedBox(width: 8),
        ElevatedButton(onPressed: controller.increment, child: const Text('+1')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Task list — ObservableList + a Computed summary derived from it.
// ---------------------------------------------------------------------------

class Task {
  Task(this.title, {this.done = false});
  final String title;
  bool done;
}

class TaskListController with ScopedObserverMixin {
  final ObservableList<Task> tasks = <Task>[
    Task('Write README'),
    Task('Wire up VM Service extensions', done: true),
    Task('Build the extension panel'),
  ].obs;

  late final Computed<String> summary = scoped(
    () => Computed(() {
      final int done = tasks.where((t) => t.done).length;
      return '$done of ${tasks.length} done';
    }),
  );

  void addTask(String title) {
    if (title.trim().isEmpty) return;
    tasks.add(Task(title.trim()));
  }

  void toggle(Task task) {
    // ObservableList has no refresh() (that's Observable-only, for a
    // single mutable value held in place) — replace the element instead,
    // which the list's [] setter always notifies as a structural change.
    final int index = tasks.indexOf(task);
    if (index == -1) return;
    tasks[index] = Task(task.title, done: !task.done);
  }

  void removeTask(Task task) => tasks.remove(task);

  void dispose() {
    tasks.close();
    disposeScope();
  }
}

class _TaskListDemo extends StatefulWidget {
  const _TaskListDemo({required this.controller});

  final TaskListController controller;

  @override
  State<_TaskListDemo> createState() => _TaskListDemoState();
}

class _TaskListDemoState extends State<_TaskListDemo> {
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Observer(() => Text(widget.controller.summary.value)),
        const SizedBox(height: 8),
        Observer(
          () => Column(
            children: [
              for (final task in widget.controller.tasks)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: task.done,
                  title: Text(task.title),
                  onChanged: (_) => widget.controller.toggle(task),
                  secondary: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => widget.controller.removeTask(task),
                  ),
                ),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                decoration: const InputDecoration(hintText: 'New task'),
                onSubmitted: (value) {
                  widget.controller.addTask(value);
                  _textController.clear();
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                widget.controller.addTask(_textController.text);
                _textController.clear();
              },
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Search — debounce worker driving a simulated lookup.
// ---------------------------------------------------------------------------

class SearchController {
  final query = ''.obs;
  final results = <String>[].obs;

  static const _catalog = [
    'Observable',
    'Observer',
    'Computed',
    'ObservableList',
    'ObservableFuture',
    'ObservableStream',
    'ReactiveScope',
    'ScopedObserverMixin',
    'effect',
    'debounce',
    'interval',
    'once',
    'ever',
  ];

  late final Workers _workers = Workers([
    debounce<String>(query, _search, time: const Duration(milliseconds: 300)),
  ]);

  Future<void> _search(String value) async {
    final needle = value.trim().toLowerCase();
    if (needle.isEmpty) {
      results.clear();
      return;
    }
    results.assignAll(_catalog.where((e) => e.toLowerCase().contains(needle)));
  }

  void dispose() {
    _workers.dispose();
    query.close();
    results.close();
  }
}

class _SearchDemo extends StatelessWidget {
  const _SearchDemo({required this.controller});

  final SearchController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search all_observer symbols…',
          ),
          onChanged: controller.query.setValue,
        ),
        const SizedBox(height: 8),
        Observer(
          () => Wrap(
            spacing: 8,
            children: [for (final r in controller.results) Chip(label: Text(r))],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Profile — ObservableFuture: loading / data / error, with a manual
//    refresh and a "fail" toggle so the DevTools panel sees an error node
//    too, not just the happy path.
// ---------------------------------------------------------------------------

class AsyncProfileController with ScopedObserverMixin {
  AsyncProfileController() {
    // ReactiveScope/ScopedObserverMixin auto-capture Computed, effect() and
    // workers — not ObservableFuture (an Observable subclass, like plain
    // Observable it's explicitly excluded from auto-capture per the docs).
    // Register its close() by hand via autoDispose so disposeScope() still
    // covers it.
    profile = ObservableFuture<String>(_fetchProfile, autoStart: false);
    autoDispose(profile.close);
  }

  bool _forceError = false;

  late final ObservableFuture<String> profile;

  Future<String> _fetchProfile() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    if (_forceError) {
      throw StateError('Simulated profile load failure');
    }
    return 'Carlos Castro';
  }

  Future<void> load() => profile.run();
  Future<void> refresh() => profile.refresh();

  void toggleForceError(bool value) => _forceError = value;

  void dispose() {
    disposeScope();
  }
}

class _ProfileDemo extends StatefulWidget {
  const _ProfileDemo({required this.controller});

  final AsyncProfileController controller;

  @override
  State<_ProfileDemo> createState() => _ProfileDemoState();
}

class _ProfileDemoState extends State<_ProfileDemo> {
  bool _forceError = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Observer(
          () => widget.controller.profile.value.when(
            loading: (previousData) => Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(previousData ?? 'Loading…'),
              ],
            ),
            data: (profile) => Text('Loaded: $profile'),
            error: (error, _) => Text(
              'Error: $error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilterChip(
              label: const Text('Force error'),
              selected: _forceError,
              onSelected: (value) => setState(() {
                _forceError = value;
                widget.controller.toggleForceError(value);
              }),
            ),
            const Spacer(),
            OutlinedButton(
              onPressed: widget.controller.load,
              child: const Text('Load'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: widget.controller.refresh,
              child: const Text('Refresh'),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Dynamic counters — each has its own ReactiveScope, created/disposed at
//    runtime. Exercises NodeCreated/NodeDisposed/ScopeCreated/ScopeDisposed
//    live, which the static demos above don't: nothing above ever disposes
//    a node while the app runs.
// ---------------------------------------------------------------------------

class ManagedCounter {
  ManagedCounter(this.id) {
    // Plain Observables are deliberately not auto-captured by
    // ReactiveScope (they hold no resource beyond their listener list) —
    // register the close() by hand so scope.dispose() still tears it down.
    count = Observable<int>(0, name: 'counter_$id');
    scope.add(count.close);
    doubled = scope.run(() => Computed<int>(() => count.value * 2, name: 'doubled_$id'));
  }

  final int id;
  final ReactiveScope scope = ReactiveScope();
  late final Observable<int> count;
  late final Computed<int> doubled;

  void increment() => count.value++;

  void dispose() => scope.dispose();
}

class DynamicCountersController {
  final ObservableList<ManagedCounter> counters = <ManagedCounter>[].obs;
  int _nextId = 1;

  void add() {
    counters.add(ManagedCounter(_nextId++));
  }

  void removeLast() {
    if (counters.isEmpty) return;
    final ManagedCounter last = counters.removeAt(counters.length - 1);
    last.dispose();
  }

  void dispose() {
    for (final counter in counters) {
      counter.dispose();
    }
    counters.close();
  }
}

class _DynamicCountersDemo extends StatelessWidget {
  const _DynamicCountersDemo({required this.controller});

  final DynamicCountersController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: controller.removeLast,
              icon: const Icon(Icons.remove),
              label: const Text('Remove last'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: controller.add,
              icon: const Icon(Icons.add),
              label: const Text('Add counter'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Observer(
          () => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final managed in controller.counters)
                Observer(
                  () => Chip(
                    label: Text('#${managed.id}: ${managed.count.value} (×2=${managed.doubled.value})'),
                    onDeleted: managed.increment,
                    deleteIcon: const Icon(Icons.add_circle_outline, size: 18),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
