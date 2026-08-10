package com.everything.everything

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray

/**
 * "Today's habits" — up to six rows, each tappable to toggle completion via a
 * background Dart callback (no app launch needed).
 */
class HabitsWidgetProvider : AppWidgetProvider() {

    private val rowIds = intArrayOf(
        R.id.habit_row_0, R.id.habit_row_1, R.id.habit_row_2,
        R.id.habit_row_3, R.id.habit_row_4, R.id.habit_row_5,
    )
    private val titleIds = intArrayOf(
        R.id.habit_title_0, R.id.habit_title_1, R.id.habit_title_2,
        R.id.habit_title_3, R.id.habit_title_4, R.id.habit_title_5,
    )
    private val checkIds = intArrayOf(
        R.id.habit_check_0, R.id.habit_check_1, R.id.habit_check_2,
        R.id.habit_check_3, R.id.habit_check_4, R.id.habit_check_5,
    )

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_habits)

            // Header opens the app.
            views.setOnClickPendingIntent(
                R.id.widget_header,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("everything://open")
                )
            )

            val raw = HomeWidgetPlugin.getData(context).getString("habits_data", "[]")
            val habits = try { JSONArray(raw) } catch (e: Exception) { JSONArray() }

            views.setViewVisibility(
                R.id.widget_empty,
                if (habits.length() == 0) View.VISIBLE else View.GONE
            )

            for (i in rowIds.indices) {
                if (i < habits.length()) {
                    val habit = habits.getJSONObject(i)
                    val done = habit.optBoolean("done", false)
                    views.setViewVisibility(rowIds[i], View.VISIBLE)
                    views.setTextViewText(titleIds[i], habit.optString("title"))
                    views.setImageViewResource(
                        checkIds[i],
                        if (done) android.R.drawable.checkbox_on_background
                        else android.R.drawable.checkbox_off_background
                    )
                    views.setOnClickPendingIntent(
                        rowIds[i],
                        HomeWidgetBackgroundIntent.getBroadcast(
                            context,
                            Uri.parse("everything://togglehabit?id=" + habit.optString("id"))
                        )
                    )
                } else {
                    views.setViewVisibility(rowIds[i], View.GONE)
                }
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
