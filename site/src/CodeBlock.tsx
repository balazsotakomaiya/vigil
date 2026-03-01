import { useEffect, useState } from 'react';
import { codeToHtml } from 'shiki';

export function CodeBlock({ code, className }: { code: string; className?: string }) {
	const [copied, setCopied] = useState(false);
	const [html, setHtml] = useState<string>('');

	useEffect(() => {
		codeToHtml(code.trim(), {
			lang: 'dart',
			theme: 'one-dark-pro',
		}).then(setHtml);
	}, [code]);

	const handleCopy = () => {
		navigator.clipboard.writeText(code);
		setCopied(true);
		setTimeout(() => setCopied(false), 1500);
	};

	return (
		<div className={`code-block-wrap ${className ?? ''}`}>
			<button type="button" className="code-copy-btn" onClick={handleCopy} aria-label="Copy code">
				{copied ? (
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
						<title>Copied</title>
						<polyline points="20 6 9 17 4 12" />
					</svg>
				) : (
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
						<title>Copy</title>
						<rect x="9" y="9" width="13" height="13" rx="2" ry="2" />
						<path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
					</svg>
				)}
			</button>
			{html ? (
				<div className="code-block" dangerouslySetInnerHTML={{ __html: html }} />
			) : (
				<pre className="code-block">
					<code>{code.trim()}</code>
				</pre>
			)}
		</div>
	);
}
