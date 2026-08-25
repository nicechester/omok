const { onValueWritten } = require("firebase-functions/v2/database");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { initializeApp } = require("firebase-admin/app");
const { getDatabase } = require("firebase-admin/database");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

const logger = require("firebase-functions/logger");

exports.notifyTurn = onValueWritten("/omok/games/{gameId}/turn", async (event) => {
  const gameId = event.params.gameId;
  const currentTurn = event.data.after.val();
  logger.info("notifyTurn triggered", { gameId, currentTurn });
  
  if (!currentTurn) {
    logger.info("No currentTurn, exiting");
    return;
  }

  const db = getDatabase();
  const gameSnap = await db.ref(`/omok/games/${gameId}`).get();
  const game = gameSnap.val();
  
  if (!game || game.status !== "playing") {
    logger.info("Game not playing", { status: game?.status });
    return;
  }

  const players = game.players || {};
  const playerToNotify = Object.keys(players).find((u) => players[u]?.color === currentTurn);
  logger.info("Player to notify", { playerToNotify, currentTurn });

  if (!playerToNotify) {
    logger.info("No player to notify");
    return;
  }

  const tokenSnap = await db.ref(`/omok/users/${playerToNotify}/fcmToken`).get();
  const token = tokenSnap.val();
  logger.info("FCM token", { hasToken: !!token });

  if (!token) {
    logger.info("No FCM token found");
    return;
  }

  const opponentColor = currentTurn === "black" ? "white" : "black";
  const opponentName = Object.values(players).find((p) => p?.color === opponentColor)?.name || "Opponent";

  try {
    await getMessaging().send({
      token,
      notification: {
        title: "Your Turn!",
        body: `${opponentName} made a move`,
      },
      data: { gameId },
      apns: { payload: { aps: { sound: "default", badge: 1 } } },
    });
    logger.info("Notification sent successfully");
  } catch (error) {
    logger.error("Failed to send notification", { error: error.message });
  }
});

exports.cleanupOldGames = onSchedule("every 24 hours", async () => {
  const db = getDatabase();
  const cutoff = Date.now() - 3 * 24 * 60 * 60 * 1000;

  // 1. Delete stale games and their audio
  const gamesSnap = await db.ref("/omok/games").orderByChild("updatedAt").endAt(cutoff).get();
  const updates = {};
  if (gamesSnap.exists()) {
    gamesSnap.forEach((child) => {
      updates[`/omok/games/${child.key}`] = null;
      updates[`/omok/audio/${child.key}`] = null;
    });
    await db.ref().update(updates);
    logger.info("Cleaned up old games", { count: Object.keys(updates).length / 2 });
  } else {
    logger.info("No old games to clean up");
  }

  // 2. Delete users not referenced in any remaining game
  const [allGamesSnap, allUsersSnap] = await Promise.all([
    db.ref("/omok/games").get(),
    db.ref("/omok/users").get(),
  ]);

  if (!allUsersSnap.exists()) return;

  // Collect all uids referenced in remaining games
  const activeUids = new Set();
  if (allGamesSnap.exists()) {
    allGamesSnap.forEach((gameChild) => {
      const players = gameChild.val()?.players || {};
      Object.keys(players).forEach((uid) => activeUids.add(uid));
    });
  }

  // Delete user nodes not in any game
  const userUpdates = {};
  allUsersSnap.forEach((userChild) => {
    if (!activeUids.has(userChild.key)) {
      userUpdates[`/omok/users/${userChild.key}`] = null;
    }
  });

  if (Object.keys(userUpdates).length > 0) {
    await db.ref().update(userUpdates);
    logger.info("Cleaned up orphaned users", { count: Object.keys(userUpdates).length });
  } else {
    logger.info("No orphaned users to clean up");
  }
});
