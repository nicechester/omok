const { onValueWritten } = require("firebase-functions/v2/database");
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
