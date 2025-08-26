<script lang="ts">
	import { onMount } from 'svelte';
	import { toast } from 'svelte-sonner';
	import { config } from '$lib/stores';
	import { getClaudeCodeStatus, updateClaudeCodeSettings, installClaudeCLI, testClaudeCode } from '$lib/apis/claudecode';
	import SensitiveInput from '$lib/components/common/SensitiveInput.svelte';
	import Spinner from '$lib/components/common/Spinner.svelte';
	
	let loading = false;
	let installing = false;
	let testing = false;
	
	// Claude Code settings
	let enabled = false;
	let oauthToken = '';
	let commandPath = 'claude';
	let timeout = 60;
	let streamResponses = false;
	let maxContextMessages = 10;
	let autoInstall = true;
	
	// Status
	let nodeInstalled = false;
	let nodeVersion = '';
	let claudeCliInstalled = false;
	let claudeCliVersion = '';
	let oauthConfigured = false;
	
	// Test message
	let testMessage = 'Hello, Claude!';
	let testResult = '';
	
	async function loadStatus() {
		loading = true;
		try {
			const status = await getClaudeCodeStatus();
			
			// Update settings
			enabled = status.settings.enabled;
			commandPath = status.settings.command_path;
			timeout = status.settings.timeout;
			streamResponses = status.settings.stream_responses;
			maxContextMessages = status.settings.max_context_messages;
			autoInstall = status.settings.auto_install;
			
			// Update status
			nodeInstalled = status.node.installed;
			nodeVersion = status.node.version || '';
			claudeCliInstalled = status.claude_cli.installed;
			claudeCliVersion = status.claude_cli.version || '';
			oauthConfigured = status.oauth_configured;
			
			// Load masked token if configured
			if (oauthConfigured) {
				const settings = await getClaudeCodeSettings();
				oauthToken = settings.oauth_token || '';
			}
		} catch (err) {
			toast.error('Failed to load Claude Code status');
			console.error(err);
		} finally {
			loading = false;
		}
	}
	
	async function saveSettings() {
		loading = true;
		try {
			const settings = {
				enabled,
				oauth_token: oauthToken,
				command_path: commandPath,
				timeout,
				stream_responses: streamResponses,
				max_context_messages: maxContextMessages,
				auto_install: autoInstall
			};
			
			await updateClaudeCodeSettings(settings);
			toast.success('Claude Code settings saved');
			
			// Reload status to get updated info
			await loadStatus();
		} catch (err) {
			toast.error('Failed to save settings');
			console.error(err);
		} finally {
			loading = false;
		}
	}
	
	async function installCLI() {
		installing = true;
		try {
			const result = await installClaudeCLI();
			
			if (result.node?.installed && result.claude_cli?.installed) {
				toast.success('Claude CLI installed successfully');
			} else {
				let message = 'Installation partially completed:\n';
				if (!result.node?.installed) {
					message += `Node.js: ${result.node?.message || 'Failed'}\n`;
				}
				if (!result.claude_cli?.installed) {
					message += `Claude CLI: ${result.claude_cli?.message || 'Failed'}`;
				}
				toast.warning(message);
			}
			
			// Reload status
			await loadStatus();
		} catch (err) {
			toast.error('Installation failed');
			console.error(err);
		} finally {
			installing = false;
		}
	}
	
	async function testClaude() {
		testing = true;
		testResult = '';
		try {
			const result = await testClaudeCode(testMessage);
			
			if (result.success) {
				testResult = result.response;
				toast.success('Test successful');
			} else {
				testResult = `Error: ${result.error}`;
				toast.error('Test failed');
			}
		} catch (err) {
			testResult = `Error: ${err}`;
			toast.error('Test failed');
		} finally {
			testing = false;
		}
	}
	
	onMount(() => {
		loadStatus();
	});
</script>

<div class="flex flex-col h-full justify-between text-sm">
	<div class="overflow-y-scroll h-full">
		<div class="flex flex-col md:flex-row gap-2">
			<div class="flex-1">
				<div class="mb-6">
					<h2 class="text-base font-medium">Claude Code Integration</h2>
					<p class="text-xs text-gray-500 dark:text-gray-400 mt-1">
						Configure Claude Code CLI for advanced AI-powered coding assistance
					</p>
				</div>

				<!-- Status Section -->
				<div class="mb-6 p-4 rounded-lg bg-gray-50 dark:bg-gray-800">
					<h3 class="text-sm font-medium mb-3">System Status</h3>
					
					<div class="space-y-2">
						<div class="flex justify-between items-center">
							<span class="text-xs">Node.js</span>
							{#if nodeInstalled}
								<span class="text-xs text-green-600 dark:text-green-400">
									✓ Installed {nodeVersion ? `(${nodeVersion})` : ''}
								</span>
							{:else}
								<span class="text-xs text-red-600 dark:text-red-400">✗ Not installed</span>
							{/if}
						</div>
						
						<div class="flex justify-between items-center">
							<span class="text-xs">Claude CLI</span>
							{#if claudeCliInstalled}
								<span class="text-xs text-green-600 dark:text-green-400">
									✓ Installed {claudeCliVersion ? `(${claudeCliVersion})` : ''}
								</span>
							{:else}
								<span class="text-xs text-red-600 dark:text-red-400">✗ Not installed</span>
							{/if}
						</div>
						
						<div class="flex justify-between items-center">
							<span class="text-xs">OAuth Token</span>
							{#if oauthConfigured}
								<span class="text-xs text-green-600 dark:text-green-400">✓ Configured</span>
							{:else}
								<span class="text-xs text-yellow-600 dark:text-yellow-400">⚠ Not configured</span>
							{/if}
						</div>
					</div>
					
					{#if !nodeInstalled || !claudeCliInstalled}
						<button
							class="mt-3 px-3 py-1 text-xs bg-blue-600 hover:bg-blue-700 text-white rounded transition"
							on:click={installCLI}
							disabled={installing}
						>
							{#if installing}
								<Spinner className="inline w-3 h-3 mr-1" />
								Installing...
							{:else}
								Install Dependencies
							{/if}
						</button>
					{/if}
				</div>

				<!-- Settings Section -->
				<div class="space-y-4">
					<!-- Enable/Disable Toggle -->
					<div class="flex items-center justify-between">
						<div>
							<label for="claude-enabled" class="text-sm font-medium">
								Enable Claude Code
							</label>
							<p class="text-xs text-gray-500 dark:text-gray-400">
								Enable Claude Code integration in chat
							</p>
						</div>
						<input
							id="claude-enabled"
							type="checkbox"
							bind:checked={enabled}
							class="rounded"
							disabled={!claudeCliInstalled || !oauthConfigured}
						/>
					</div>

					<!-- OAuth Token -->
					<div>
						<label for="oauth-token" class="block text-sm font-medium mb-1">
							Claude Pro OAuth Token
						</label>
						<p class="text-xs text-gray-500 dark:text-gray-400 mb-2">
							Get your token by running: <code class="px-1 py-0.5 bg-gray-100 dark:bg-gray-800 rounded">npx @anthropic-ai/claude-code login</code>
						</p>
						<SensitiveInput
							id="oauth-token"
							bind:value={oauthToken}
							placeholder="sk-ant-oat01-..."
						/>
					</div>

					<!-- Advanced Settings -->
					<details class="border-t pt-4">
						<summary class="cursor-pointer text-sm font-medium">Advanced Settings</summary>
						
						<div class="mt-4 space-y-4">
							<!-- Command Path -->
							<div>
								<label for="command-path" class="block text-sm font-medium mb-1">
									Claude CLI Path
								</label>
								<input
									id="command-path"
									type="text"
									bind:value={commandPath}
									class="w-full rounded px-3 py-2 text-sm border dark:border-gray-600 dark:bg-gray-800"
								/>
							</div>

							<!-- Timeout -->
							<div>
								<label for="timeout" class="block text-sm font-medium mb-1">
									Command Timeout (seconds)
								</label>
								<input
									id="timeout"
									type="number"
									bind:value={timeout}
									min="10"
									max="300"
									class="w-full rounded px-3 py-2 text-sm border dark:border-gray-600 dark:bg-gray-800"
								/>
							</div>

							<!-- Max Context Messages -->
							<div>
								<label for="max-context" class="block text-sm font-medium mb-1">
									Max Context Messages
								</label>
								<input
									id="max-context"
									type="number"
									bind:value={maxContextMessages}
									min="1"
									max="50"
									class="w-full rounded px-3 py-2 text-sm border dark:border-gray-600 dark:bg-gray-800"
								/>
							</div>

							<!-- Stream Responses -->
							<div class="flex items-center justify-between">
								<label for="stream-responses" class="text-sm font-medium">
									Stream Responses
								</label>
								<input
									id="stream-responses"
									type="checkbox"
									bind:checked={streamResponses}
									class="rounded"
								/>
							</div>

							<!-- Auto Install -->
							<div class="flex items-center justify-between">
								<label for="auto-install" class="text-sm font-medium">
									Auto-install CLI
								</label>
								<input
									id="auto-install"
									type="checkbox"
									bind:checked={autoInstall}
									class="rounded"
								/>
							</div>
						</div>
					</details>

					<!-- Test Section -->
					{#if enabled && oauthConfigured}
						<div class="border-t pt-4">
							<h3 class="text-sm font-medium mb-2">Test Claude Code</h3>
							<div class="flex gap-2">
								<input
									type="text"
									bind:value={testMessage}
									placeholder="Enter a test message"
									class="flex-1 rounded px-3 py-2 text-sm border dark:border-gray-600 dark:bg-gray-800"
								/>
								<button
									class="px-3 py-1 text-xs bg-green-600 hover:bg-green-700 text-white rounded transition"
									on:click={testClaude}
									disabled={testing}
								>
									{#if testing}
										<Spinner className="inline w-3 h-3" />
									{:else}
										Test
									{/if}
								</button>
							</div>
							
							{#if testResult}
								<div class="mt-2 p-2 bg-gray-100 dark:bg-gray-800 rounded text-xs">
									<pre class="whitespace-pre-wrap">{testResult}</pre>
								</div>
							{/if}
						</div>
					{/if}
				</div>
			</div>
		</div>
	</div>

	<div class="flex justify-end pt-4 border-t">
		<button
			class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded transition"
			on:click={saveSettings}
			disabled={loading}
		>
			{#if loading}
				<Spinner className="inline w-4 h-4 mr-1" />
				Saving...
			{:else}
				Save Settings
			{/if}
		</button>
	</div>
</div>