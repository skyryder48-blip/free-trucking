<script>
  import { fetchNUI } from '../lib/nui.js';
  import { cdlTestData } from '../lib/stores.js';

  let answers = {};
  let submitted = false;
  let currentQuestion = 0;

  $: test = $cdlTestData;
  $: questions = test?.questions || [];
  $: totalQuestions = questions.length;
  $: allAnswered = Object.keys(answers).length === totalQuestions;

  function selectAnswer(questionIndex, optionKey) {
    if (submitted) return;
    answers[questionIndex] = optionKey;
    answers = answers; // trigger reactivity
  }

  async function submitTest() {
    if (submitted || !allAnswered) return;
    submitted = true;

    // Build answers array in order
    const orderedAnswers = [];
    for (let i = 0; i < totalQuestions; i++) {
      orderedAnswers.push(answers[i] || '');
    }

    await fetchNUI('trucking:submitCDLTest', {
      testType: test.testType,
      answers: orderedAnswers,
    });
  }

  function closeTest() {
    fetchNUI('trucking:closeCDLTest');
  }

  function goToQuestion(index) {
    if (index >= 0 && index < totalQuestions) {
      currentQuestion = index;
    }
  }

  const optionLabels = { a: 'A', b: 'B', c: 'C', d: 'D' };
</script>

<div class="cdl-test">
  <div class="test-header">
    <h2>CDL Written Test</h2>
    <span class="test-type">{test?.testType?.replace('_', ' ').toUpperCase() || 'CDL'}</span>
    <button class="close-btn" on:click={closeTest} aria-label="Close">
      <svg width="14" height="14" viewBox="0 0 16 16" fill="none">
        <path d="M12 4L4 12M4 4L12 12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
      </svg>
    </button>
  </div>

  <!-- Progress bar -->
  <div class="progress-bar">
    {#each Array(totalQuestions) as _, i}
      <button
        class="progress-dot"
        class:answered={answers[i] !== undefined}
        class:current={currentQuestion === i}
        on:click={() => goToQuestion(i)}
        aria-label="Question {i + 1}"
      >{i + 1}</button>
    {/each}
  </div>

  <div class="progress-text">
    {Object.keys(answers).length} / {totalQuestions} answered
  </div>

  <!-- Current question -->
  {#if questions[currentQuestion]}
    {@const q = questions[currentQuestion]}
    <div class="question-card">
      <div class="question-number">Question {currentQuestion + 1}</div>
      <p class="question-text">{q.question}</p>

      <div class="options">
        {#each Object.entries(q.options) as [key, text]}
          <button
            class="option-btn"
            class:selected={answers[currentQuestion] === key}
            disabled={submitted}
            on:click={() => selectAnswer(currentQuestion, key)}
          >
            <span class="option-key">{optionLabels[key] || key}</span>
            <span class="option-text">{text}</span>
          </button>
        {/each}
      </div>
    </div>

    <!-- Navigation -->
    <div class="nav-buttons">
      <button
        class="nav-btn"
        disabled={currentQuestion === 0}
        on:click={() => goToQuestion(currentQuestion - 1)}
      >Previous</button>

      {#if currentQuestion < totalQuestions - 1}
        <button
          class="nav-btn nav-next"
          on:click={() => goToQuestion(currentQuestion + 1)}
        >Next</button>
      {:else}
        <button
          class="nav-btn nav-submit"
          disabled={!allAnswered || submitted}
          on:click={submitTest}
        >{submitted ? 'Submitting...' : 'Submit Test'}</button>
      {/if}
    </div>
  {/if}
</div>

<style>
  .cdl-test {
    padding: var(--spacing-md, 12px);
  }

  .test-header {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm, 8px);
    margin-bottom: var(--spacing-md, 12px);
  }

  .test-header h2 {
    margin: 0;
    font-size: 18px;
    color: var(--white, #fff);
  }

  .test-type {
    font-size: 11px;
    color: var(--orange, #C83803);
    background: rgba(200, 56, 3, 0.15);
    padding: 2px 8px;
    border-radius: var(--radius-sm, 4px);
    font-weight: 700;
    letter-spacing: 0.05em;
  }

  .test-header .close-btn {
    margin-left: auto;
    background: none;
    border: none;
    color: var(--muted, #A8B4C8);
    cursor: pointer;
    padding: 4px;
  }

  .test-header .close-btn:hover {
    color: var(--white, #fff);
  }

  .progress-bar {
    display: flex;
    gap: 4px;
    flex-wrap: wrap;
    margin-bottom: 4px;
  }

  .progress-dot {
    width: 28px;
    height: 28px;
    border-radius: var(--radius-sm, 4px);
    border: 1px solid var(--border, #1E3A6E);
    background: var(--navy-dark, #051229);
    color: var(--muted, #A8B4C8);
    font-size: 11px;
    font-weight: 600;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .progress-dot.answered {
    background: rgba(200, 56, 3, 0.2);
    border-color: var(--orange, #C83803);
    color: var(--orange, #C83803);
  }

  .progress-dot.current {
    border-color: var(--white, #fff);
    color: var(--white, #fff);
  }

  .progress-text {
    font-size: 12px;
    color: var(--muted, #A8B4C8);
    margin-bottom: var(--spacing-md, 12px);
  }

  .question-card {
    background: var(--navy-dark, #051229);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: var(--radius-md, 8px);
    padding: var(--spacing-md, 12px);
    margin-bottom: var(--spacing-md, 12px);
  }

  .question-number {
    font-size: 11px;
    color: var(--orange, #C83803);
    text-transform: uppercase;
    letter-spacing: 0.05em;
    font-weight: 700;
    margin-bottom: 6px;
  }

  .question-text {
    color: var(--white, #fff);
    font-size: 14px;
    line-height: 1.5;
    margin: 0 0 var(--spacing-md, 12px) 0;
  }

  .options {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .option-btn {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm, 8px);
    padding: 8px 12px;
    background: rgba(19, 46, 92, 0.4);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: var(--radius-sm, 4px);
    cursor: pointer;
    text-align: left;
    transition: border-color 0.15s ease, background 0.15s ease;
    color: var(--white, #fff);
  }

  .option-btn:hover:not(:disabled) {
    border-color: var(--orange, #C83803);
    background: rgba(200, 56, 3, 0.08);
  }

  .option-btn.selected {
    border-color: var(--orange, #C83803);
    background: rgba(200, 56, 3, 0.15);
  }

  .option-btn:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .option-key {
    width: 24px;
    height: 24px;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 50%;
    background: var(--navy-dark, #051229);
    border: 1px solid var(--border, #1E3A6E);
    font-size: 11px;
    font-weight: 700;
    color: var(--muted, #A8B4C8);
    flex-shrink: 0;
  }

  .option-btn.selected .option-key {
    background: var(--orange, #C83803);
    border-color: var(--orange, #C83803);
    color: var(--white, #fff);
  }

  .option-text {
    font-size: 13px;
    line-height: 1.4;
  }

  .nav-buttons {
    display: flex;
    justify-content: space-between;
    gap: var(--spacing-sm, 8px);
  }

  .nav-btn {
    padding: 8px 20px;
    border: 1px solid var(--border, #1E3A6E);
    border-radius: var(--radius-sm, 4px);
    background: var(--navy-dark, #051229);
    color: var(--muted, #A8B4C8);
    font-weight: 600;
    font-size: 13px;
    cursor: pointer;
    transition: color 0.15s, border-color 0.15s;
  }

  .nav-btn:hover:not(:disabled) {
    color: var(--white, #fff);
    border-color: var(--white, #fff);
  }

  .nav-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .nav-next {
    margin-left: auto;
  }

  .nav-submit {
    margin-left: auto;
    background: var(--orange, #C83803);
    border-color: var(--orange, #C83803);
    color: var(--white, #fff);
  }

  .nav-submit:hover:not(:disabled) {
    background: #e04004;
    border-color: #e04004;
  }
</style>
