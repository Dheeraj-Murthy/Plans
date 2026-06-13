package com.plansapp.widget

import android.content.Intent
import android.widget.RemoteViewsService

class TaskRemoteViewsService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsService.RemoteViewsFactory {
        return TaskRemoteViewsFactory(applicationContext, intent)
    }
}