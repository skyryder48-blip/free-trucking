import { writable } from 'svelte/store';

/** Current active screen name */
export const currentScreen = writable('home');

/** Player driver data: rep score, tier, licenses, certs, stats */
export const playerData = writable({
  citizenid: '',
  name: '',
  reputationScore: 500,
  reputationTier: 'developing',
  suspendedUntil: null,
  totalLoadsCompleted: 0,
  totalLoadsFailed: 0,
  totalLoadsStolen: 0,
  totalDistanceDriven: 0,
  totalEarnings: 0,
  licenses: [],
  certifications: [],
  leonAccess: false,
});

/** Current active load data */
export const activeLoad = writable(null);

/** Available loads from the job board */
export const boardData = writable({
  standard: [],
  supplier: [],
  open: [],
  routes: [],
});

/** Active insurance policies */
export const insuranceData = writable({
  policies: [],
  availablePlans: [],
});

/** Company info and members */
export const companyData = writable({
  company: null,
  members: [],
  activeClaims: [],
});

/** HUD overlay state for the in-world active load display */
export const hudData = writable({
  visible: false,
  bolNumber: '',
  cargoType: '',
  destination: '',
  distanceRemaining: 0,
  timeRemaining: 0,
  temperature: null,
  tempInRange: true,
  integrity: 100,
  sealStatus: 'not_applied',
  borderState: 'normal', // 'normal' | 'warning' | 'critical'
});

/** Convoy group data */
export const convoyData = writable({
  active: false,
  convoyId: null,
  leader: null,
  members: [],
  bonusPercentage: 0,
});

/** CDL written test data: { testType, questions, questionCount, passScore, fee } */
export const cdlTestData = writable(null);

/** HAZMAT briefing data: { topics } */
export const hazmatBriefingData = writable(null);

/** CDL test result: { passed, score, required, totalQuestions } */
export const cdlTestResult = writable(null);

/** Admin panel data */
export const adminData = writable({
  stats: null,
  activeLoads: [],
  activeSurges: [],
  boardState: {},
  economySettings: { multiplier: 1.0 },
  pendingClaims: [],
  playerProfile: null,
});

/** Payout breakdown data for completed loads */
export const payoutData = writable(null);

/** BOL detail overlay data */
export const bolDetailData = writable(null);

/** Dispatcher UI data */
export const dispatcherData = writable(null);

/** Tutorial HUD stage data */
export const tutorialData = writable(null);

/** NUI visibility state */
export const visibility = writable(false);
