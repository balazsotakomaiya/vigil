import type { ReactNode } from 'react';
import { useState } from 'react';
import { CodeBlock } from './CodeBlock';

type PkgManager = 'flutter' | 'pubspec';

const INSTALL_CMDS: Record<PkgManager, string> = {
	flutter: 'flutter pub add vigil',
	pubspec: 'vigil: ^0.1.0',
};

const HERO_EXAMPLE = `class _TodosState extends State<TodosPage> with QueryMixin {
  late final todos = query<List<Todo>>(
    ['todos'],
    () => api.fetchTodos(),
    stale: Duration(minutes: 5),
  );

  @override
  Widget build(BuildContext context) {
    if (todos.isLoading) return CircularProgressIndicator();
    if (todos.hasError) return Text('\${todos.error}');
    return TodoList(todos.data!);
  }
}`;

const MUTATION_EXAMPLE = `late final addTodo = mutation<Todo, String>(
  (title) => api.createTodo(title),
  invalidates: [['todos']],
);

// In a callback:
addTodo.mutate('Buy groceries');`;

const INFINITE_EXAMPLE = `late final todos = infiniteQuery<List<Todo>, int>(
  ['todos'],
  (page) => api.fetchTodos(page: page),
  initialPageParam: 1,
  getNextPageParam: (lastPage, allPages) =>
      lastPage.length == 20 ? allPages.length + 1 : null,
);

// In your ListView:
if (todos.hasNextPage) {
  todos.fetchNextPage();
}`;

const OPTIMISTIC_EXAMPLE = `late final toggleTodo = mutation<void, Todo>(
  (todo) => api.updateTodo(todo.copyWith(done: !todo.done)),
  optimisticUpdate: (todo) {
    client.setQueryData<List<Todo>>(['todos'], (todos) =>
      todos.map((t) => t.id == todo.id 
        ? t.copyWith(done: !t.done) : t).toList(),
    );
  },
  onError: (error, rollback) => rollback(),
);`;

const POLLING_EXAMPLE = `late final stockPrice = query<double>(
  ['stock', 'AAPL'],
  () => api.fetchPrice('AAPL'),
  refetchInterval: Duration(seconds: 30),
);

// Automatically pauses when:
// - App is backgrounded
// - Device goes offline`;

const DEPENDENT_EXAMPLE = `late final user = query<User>(['user'], () => api.fetchUser());

late final posts = query<List<Post>>(
  ['posts', user.data?.id],
  () => api.fetchPosts(userId: user.data!.id),
  enabled: user.data != null, // waits for user
);`;

const FeatureIcon = ({ name }: { name: string }) => {
	const icons: Record<string, ReactNode> = {
		zap: <path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z" />,
		link: <><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" /><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" /></>,
		trash: <><polyline points="3 6 5 6 21 6" /><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" /></>,
		refresh: <><polyline points="23 4 23 10 17 10" /><polyline points="1 20 1 14 7 14" /><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15" /></>,
		sparkles: <><path d="M12 3l1.5 4.5L18 9l-4.5 1.5L12 15l-1.5-4.5L6 9l4.5-1.5L12 3z" /><path d="M5 19l.5 1.5L7 21l-1.5.5L5 23l-.5-1.5L3 21l1.5-.5L5 19z" /><path d="M19 11l.5 1.5L21 13l-1.5.5-.5 1.5-.5-1.5L17 13l1.5-.5.5-1.5z" /></>,
		infinity: <path d="M18.178 8c5.096 0 5.096 8 0 8-5.095 0-7.133-8-12.267-8-4.096 0-4.096 8 0 8 5.134 0 7.172-8 12.267-8z" />,
		eye: <><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" /><circle cx="12" cy="12" r="3" /></>,
		wifi: <><path d="M5 12.55a11 11 0 0 1 14.08 0" /><path d="M1.42 9a16 16 0 0 1 21.16 0" /><path d="M8.53 16.11a6 6 0 0 1 6.95 0" /><circle cx="12" cy="20" r="1" /></>,
		feather: <path d="M20.24 12.24a6 6 0 0 0-8.49-8.49L5 10.5V19h8.5l6.74-6.76zM16 8l-2 2M4 19l4.5-4.5M14 5l4 4" />,
	};
	return (
		<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
			{icons[name]}
		</svg>
	);
};

const FEATURES = [
	{
		title: 'Stale-while-revalidate',
		desc: 'Show cached data instantly, refresh in the background. No loading spinners for repeat visits.',
		icon: 'zap',
	},
	{
		title: 'Request deduplication',
		desc: 'Multiple widgets requesting the same key share a single network request.',
		icon: 'link',
	},
	{
		title: 'Automatic GC',
		desc: 'Unused cache entries are evicted after a configurable timeout. No memory leaks.',
		icon: 'trash',
	},
	{
		title: 'Retry with jitter',
		desc: 'Failed requests retry with exponential backoff and full jitter to prevent thundering herds.',
		icon: 'refresh',
	},
	{
		title: 'Optimistic updates',
		desc: 'Update the UI immediately, automatically roll back on server failure.',
		icon: 'sparkles',
	},
	{
		title: 'Infinite queries',
		desc: 'Cursor and offset pagination with fetchNextPage() / fetchPreviousPage().',
		icon: 'infinity',
	},
	{
		title: 'Focus refetching',
		desc: 'Automatically refetch stale queries when the app returns to the foreground.',
		icon: 'eye',
	},
	{
		title: 'Network awareness',
		desc: 'Pause fetches when offline, resume seamlessly on reconnect.',
		icon: 'wifi',
	},
	{
		title: 'Zero dependencies',
		desc: 'Tiny footprint. Pure Dart + Flutter, nothing else.',
		icon: 'feather',
	},
];

const STATE_SCENARIOS = [
	{
		label: 'First load',
		hasData: 'No',
		network: 'Fetching',
		getter: 'isLoading',
		desc: 'No cached data yet, request in flight',
		code: `if (state.isLoading) {\n  return CircularProgressIndicator();\n}`,
		visual: { data: false, spinnerCenter: true },
	},
	{
		label: 'Fresh data',
		hasData: 'Yes',
		network: 'Idle',
		getter: 'isSuccess',
		desc: 'Data available, nothing happening',
		code: `if (state.isSuccess) {\n  return TodoList(state.data!);\n}`,
		visual: { data: true, spinnerCenter: false },
	},
	{
		label: 'Refreshing',
		hasData: 'Yes',
		network: 'Fetching',
		getter: 'isRefetching',
		desc: 'Showing stale data while refreshing',
		code: `if (state.isRefetching) {\n  // show data + subtle indicator\n}`,
		visual: { data: true, spinnerCorner: true },
	},
	{
		label: 'Error',
		hasData: 'No',
		network: 'Idle',
		getter: 'isError',
		desc: 'Last fetch failed',
		code: `if (state.isError) {\n  return ErrorWidget(state.error);\n}`,
		visual: { data: false, error: true },
	},
	{
		label: 'Offline',
		hasData: 'Yes',
		network: 'Paused',
		getter: 'isPaused',
		desc: 'Waiting for network connectivity',
		code: `if (state.isPaused) {\n  // show cached data + offline badge\n}`,
		visual: { data: true, paused: true },
	},
];

function InstallBlock({
	pkgManager,
	setPkgManager,
}: {
	pkgManager: PkgManager;
	setPkgManager: (pm: PkgManager) => void;
}) {
	return (
		<div className="install-block">
			<div className="pkg-tabs">
				{(Object.keys(INSTALL_CMDS) as PkgManager[]).map((pm) => (
					<button
						type="button"
						key={pm}
						className={`pkg-tab ${pm === pkgManager ? 'active' : ''}`}
						onClick={() => setPkgManager(pm)}
					>
						{pm === 'flutter' ? 'CLI' : 'pubspec.yaml'}
					</button>
				))}
			</div>
			<div className="install-cmd">
				<code>{INSTALL_CMDS[pkgManager]}</code>
				<button
					type="button"
					className="copy-btn"
					onClick={() => navigator.clipboard.writeText(INSTALL_CMDS[pkgManager])}
					aria-label="Copy to clipboard"
				>
					<svg
						width="16"
						height="16"
						viewBox="0 0 24 24"
						fill="none"
						stroke="currentColor"
						strokeWidth="2"
						strokeLinecap="round"
						strokeLinejoin="round"
						role="img"
					>
						<title>Copy</title>
						<rect x="9" y="9" width="13" height="13" rx="2" ry="2" />
						<path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
					</svg>
				</button>
			</div>
		</div>
	);
}

function FeaturesSection() {
	return (
		<section className="section" id="features">
			<div className="section-label">Features</div>
			<h2 className="section-title">Everything you need, nothing you don't</h2>
			<p className="section-desc">
				Server state is hard. Vigil handles caching, deduplication, retries, staleness, garbage collection, 
				and refetch-on-focus — so you can focus on building.
			</p>

			<div className="features-grid">
				{FEATURES.map((feature) => (
					<div key={feature.title} className="feature-card">
						<span className="feature-icon"><FeatureIcon name={feature.icon} /></span>
						<h3 className="feature-card-title">{feature.title}</h3>
						<p className="feature-card-desc">{feature.desc}</p>
					</div>
				))}
			</div>
		</section>
	);
}

function StateModelSection() {
	const [activeScenario, setActiveScenario] = useState(0);
	const scenario = STATE_SCENARIOS[activeScenario];

	return (
		<section className="section" id="state-model">
			<div className="section-label">State Model</div>
			<h2 className="section-title">Two axes, one truth</h2>
			<p className="section-desc">
				Most libraries give you loading/data/error. But what about "cached data + refreshing"? 
				Vigil tracks <strong>data</strong> and <strong>network</strong> independently.
			</p>

			<div className="state-demo">
				<div className="state-scenarios">
					{STATE_SCENARIOS.map((s, i) => (
						<button
							type="button"
							key={s.label}
							className={`state-scenario-btn ${activeScenario === i ? 'active' : ''}`}
							onClick={() => setActiveScenario(i)}
						>
							{s.label}
						</button>
					))}
				</div>

				<div className="state-visualization">
					<div className="state-phone">
						<div className="state-phone-screen">
							{scenario.visual.error ? (
								<div className="state-error">
									<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
										<circle cx="12" cy="12" r="10" />
										<line x1="12" y1="8" x2="12" y2="12" />
										<line x1="12" y1="16" x2="12.01" y2="16" />
									</svg>
									<span>Failed</span>
								</div>
							) : scenario.visual.data ? (
								<div className="state-data">
									<div className="state-data-row" />
									<div className="state-data-row" />
									<div className="state-data-row" />
								</div>
							) : (
								<div className="state-empty" />
							)}
							{scenario.visual.spinnerCenter && <div className="state-spinner state-spinner--center" />}
							{scenario.visual.spinnerCorner && <div className="state-spinner state-spinner--corner" />}
							{scenario.visual.paused && (
								<div className="state-paused">
									<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
										<line x1="1" y1="1" x2="23" y2="23" />
										<path d="M16.72 11.06A10.94 10.94 0 0 1 19 12.55" />
										<path d="M5 12.55a10.94 10.94 0 0 1 5.17-2.39" />
										<path d="M10.71 5.05A16 16 0 0 1 22.58 9" />
										<path d="M1.42 9a15.91 15.91 0 0 1 4.7-2.88" />
										<path d="M8.53 16.11a6 6 0 0 1 6.95 0" />
										<circle cx="12" cy="20" r="1" />
									</svg>
								</div>
							)}
						</div>
					</div>

					<div className="state-info">
						<div className="state-info-row">
							<span className="state-info-label">Has data?</span>
							<code className="state-info-value">{scenario.hasData}</code>
						</div>
						<div className="state-info-row">
							<span className="state-info-label">Network</span>
							<code className="state-info-value">{scenario.network}</code>
						</div>
						<div className="state-info-row">
							<span className="state-info-label">Check with</span>
							<code className="state-info-value state-info-value--getter">{scenario.getter}</code>
						</div>
						<p className="state-info-desc">{scenario.desc}</p>
						<pre className="state-code">{scenario.code}</pre>
					</div>
				</div>
			</div>
		</section>
	);
}

type UsageTab = 'query' | 'mutation' | 'infinite';

function UsageSection() {
	const [tab, setTab] = useState<UsageTab>('query');

	const examples: Record<UsageTab, { code: string; title: string; desc: string }> = {
		query: {
			title: 'Queries',
			desc: 'Fetch and cache data with automatic staleness tracking.',
			code: HERO_EXAMPLE,
		},
		mutation: {
			title: 'Mutations',
			desc: 'Write operations with automatic cache invalidation.',
			code: MUTATION_EXAMPLE,
		},
		infinite: {
			title: 'Infinite Queries',
			desc: 'Paginated fetching with cursor or offset pagination.',
			code: INFINITE_EXAMPLE,
		},
	};

	return (
		<section className="section" id="usage">
			<div className="section-label">Usage</div>
			<h2 className="section-title">Mix in and go</h2>
			<p className="section-desc">
				Add <code>QueryMixin</code> to any State class. Call <code>query()</code>, <code>mutation()</code>, 
				or <code>infiniteQuery()</code>. That's it.
			</p>

			<div className="usage-card">
				<div className="usage-tabs">
					{(Object.keys(examples) as UsageTab[]).map((t) => (
						<button
							type="button"
							key={t}
							className={`usage-tab ${tab === t ? 'active' : ''}`}
							onClick={() => setTab(t)}
						>
							{examples[t].title}
						</button>
					))}
				</div>
				<div className="usage-content">
					<p className="usage-desc">{examples[tab].desc}</p>
					<div className="usage-separator" />
					<CodeBlock code={examples[tab].code} />
				</div>
			</div>
		</section>
	);
}

function PatternsSection() {
	const [activePattern, setActivePattern] = useState<'optimistic' | 'polling' | 'dependent'>('optimistic');

	const patterns = {
		optimistic: {
			title: 'Optimistic Updates',
			desc: 'Update the UI immediately, roll back if the server rejects.',
			code: OPTIMISTIC_EXAMPLE,
		},
		polling: {
			title: 'Polling',
			desc: 'Refetch on a timer with automatic pause when backgrounded or offline.',
			code: POLLING_EXAMPLE,
		},
		dependent: {
			title: 'Dependent Queries',
			desc: 'Chain queries with the enabled option.',
			code: DEPENDENT_EXAMPLE,
		},
	};

	return (
		<section className="section" id="patterns">
			<div className="section-label">Patterns</div>
			<h2 className="section-title">Battle-tested recipes</h2>
			<p className="section-desc">
				Common patterns for real-world apps, all built into the library.
			</p>

			<div className="patterns-grid">
				<div className="patterns-nav">
					{(Object.keys(patterns) as (keyof typeof patterns)[]).map((key) => (
						<button
							type="button"
							key={key}
							className={`pattern-btn ${activePattern === key ? 'active' : ''}`}
							onClick={() => setActivePattern(key)}
						>
							<span className="pattern-btn-title">{patterns[key].title}</span>
							<span className="pattern-btn-desc">{patterns[key].desc}</span>
						</button>
					))}
				</div>
				<div className="patterns-code">
					<CodeBlock code={patterns[activePattern].code} />
				</div>
			</div>
		</section>
	);
}

function LibraryComparisonSection() {
	return (
		<section className="section" id="comparison">
			<div className="section-label">Comparison</div>
			<h2 className="section-title">What Riverpod is for, but simpler</h2>
			<p className="section-desc">
				Riverpod and Bloc solve everything. Vigil solves one thing: keeping remote data fresh. 
				Like TanStack Query replaced Redux for fetching in React, Vigil can replace what you're using Riverpod for.
			</p>

			<div className="lib-comparison">
				<div className="lib-comparison-header">
					<div className="lib-comparison-feature">Feature</div>
					<div className="lib-comparison-lib">Riverpod</div>
					<div className="lib-comparison-lib">Bloc</div>
					<div className="lib-comparison-lib lib-comparison-lib--vigil">Vigil</div>
				</div>
				{[
					{ feature: 'Caching', riverpod: 'Built-in', bloc: 'Manual', vigil: 'Built-in' },
					{ feature: 'Stale-while-revalidate', riverpod: 'DIY', bloc: 'DIY', vigil: 'Built-in' },
					{ feature: 'Request deduplication', riverpod: 'Built-in', bloc: 'No', vigil: 'Built-in' },
					{ feature: 'Background refetch', riverpod: 'DIY', bloc: 'DIY', vigil: 'Built-in' },
					{ feature: 'Retry with backoff', riverpod: 'DIY', bloc: 'DIY', vigil: 'Built-in' },
					{ feature: 'Optimistic updates', riverpod: 'DIY', bloc: 'DIY', vigil: 'Built-in' },
					{ feature: 'Infinite queries', riverpod: 'DIY', bloc: 'DIY', vigil: 'Built-in' },
					{ feature: 'Scope', riverpod: 'All state', bloc: 'All state', vigil: 'Remote data' },
				].map((row, i) => (
					<div key={i} className="lib-comparison-row">
						<div className="lib-comparison-feature">{row.feature}</div>
						<div className="lib-comparison-cell">{row.riverpod}</div>
						<div className="lib-comparison-cell">{row.bloc}</div>
						<div className="lib-comparison-cell lib-comparison-cell--vigil">{row.vigil}</div>
					</div>
				))}
			</div>
		</section>
	);
}

export function App() {
	const [pkgManager, setPkgManager] = useState<PkgManager>('flutter');

	return (
		<div className="page">
			<div className="rulers" aria-hidden="true">
				<div className="ruler ruler--v ruler--left" />
				<div className="ruler ruler--v ruler--right" />
				<div className="ruler ruler--v ruler--content-left" />
				<div className="ruler ruler--v ruler--content-right" />
				<div className="ruler ruler--h ruler--top" />
				<div className="ruler ruler--h ruler--bottom" />
			</div>

			<nav className="nav">
				<div className="nav-logo">
					<svg className="nav-eye" width="28" height="28" viewBox="0 0 52 52">
						<path className="vigil-eye-shape"
							d="M 2 26 C 12 10, 40 10, 50 26 C 40 42, 12 42, 2 26 Z"
							fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinejoin="round"/>
						<circle className="vigil-eye-iris"
							cx="26" cy="26" r="9" fill="none" stroke="currentColor" strokeWidth="1.8"/>
						<g className="vigil-eye-pupil-group">
							<circle className="vigil-eye-pupil"
								cx="26" cy="26" r="3.5" fill="currentColor"/>
						</g>
					</svg>
					<span>vigil</span>
				</div>
				<div className="nav-links">
					<a href="#features">Features</a>
					<a href="#usage">Usage</a>
					<a href="#comparison">Compare</a>
					<a
						href="https://github.com/balazsotakomaiya/vigil"
						target="_blank"
						rel="noopener noreferrer"
						className="github-star-btn"
					>
						<svg
							width="14"
							height="14"
							viewBox="0 0 24 24"
							fill="none"
							stroke="currentColor"
							strokeWidth="2"
							strokeLinecap="round"
							strokeLinejoin="round"
							role="img"
						>
							<title>Star</title>
							<polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
						</svg>
						Star on GitHub
					</a>
				</div>
			</nav>

			<header className="hero">
				<div className="hero-badge">
					<span>TanStack Query for Flutter</span>
					<span className="hero-badge-version">v0.1.0</span>
				</div>
				<h1 className="hero-title">
					Fetching that
					<br />
					just works
				</h1>
				<p className="hero-desc">
					Caching, retries, deduplication, staleness — handled.
					No code generation. No boilerplate.
				</p>

				<InstallBlock pkgManager={pkgManager} setPkgManager={setPkgManager} />

				<div className="hero-code">
					<CodeBlock code={HERO_EXAMPLE} />
				</div>
			</header>

			<div className="ruler-divider" aria-hidden="true" />
			<FeaturesSection />
			<div className="ruler-divider" aria-hidden="true" />
			<UsageSection />
			<div className="ruler-divider" aria-hidden="true" />
			<PatternsSection />
			<div className="ruler-divider" aria-hidden="true" />
			<StateModelSection />
			<div className="ruler-divider" aria-hidden="true" />
			<LibraryComparisonSection />
			<div className="ruler-divider" aria-hidden="true" />

			<footer className="footer">
				<div className="footer-inner">
					<span className="footer-logo">vigil</span>
					<span className="footer-sep">·</span>
					<a
						href="https://github.com/balazsotakomaiya/vigil"
						target="_blank"
						rel="noopener noreferrer"
					>
						GitHub
					</a>
					<span className="footer-sep">·</span>
					<a
						href="https://pub.dev/packages/vigil"
						target="_blank"
						rel="noopener noreferrer"
					>
						pub.dev
					</a>
				</div>
				<div className="footer-credit">
					Made by{' '}
					<a
						href="https://otakomaiya.com"
						target="_blank"
						rel="noopener noreferrer"
						className="footer-credit-link"
					>
						Balazs Otakomaiya
					</a>
				</div>
			</footer>
		</div>
	);
}
