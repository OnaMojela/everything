package com.everything.everything

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/** Two buttons that launch straight into recording a transaction. */
class QuickAddWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_quick_add)
            views.setOnClickPendingIntent(
                R.id.quick_add_expense,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java,
                    Uri.parse("everything://add?type=expense")
                )
            )
            views.setOnClickPendingIntent(
                R.id.quick_add_income,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java,
                    Uri.parse("everything://add?type=income")
                )
            )
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
