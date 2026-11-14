package dev.termphin.termphin

import android.os.Build
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsAnimation
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterView

/**
 * Keeps the keyboard inset Flutter lays out with equal to the window's own.
 *
 * The engine defers insets while the keyboard animates: its listener on the
 * FlutterView swallows every dispatch until the animation ends, then replays
 * the insets it saved when the animation began. An animation that is cut
 * short - the keyboard hidden while still sliding in, the app sent to the
 * background halfway - can end on insets that are no longer true, and one
 * that never reports its end leaves the listener swallowing for good. Either
 * way the terminal keeps a band the size of a keyboard that is not there,
 * and `requestApplyInsets()` cannot clear it because it goes through that
 * same listener.
 *
 * So the truth is handed to the view directly: `onApplyWindowInsets` is the
 * method the engine itself calls with each animation frame, and calling it
 * skips the listener. That happens once the last keyboard animation is over
 * and whenever the activity comes back, never in the middle of one, where it
 * would jump the layout to the final size ahead of the keyboard.
 *
 * Installed on the decor view, not the FlutterView: a view holds one
 * animation callback and the FlutterView's belongs to the engine. The decor
 * view is dispatched first, hence the `post` - by the time it runs, the
 * engine's own end-of-animation handling is done.
 *
 * Insets only animate from Android 11, and the engine only defers them
 * there, so below it this does nothing. The callback is a class of its own
 * for that: this one has to load on every version the app runs on.
 */
class ImeInsetsGuard(private val root: View) {

    private var running = 0
    private var lastStartedAt = 0L

    fun install() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        root.setWindowInsetsAnimationCallback(KeyboardAnimations())
    }

    /**
     * For the moments the activity regains the screen. An animation still
     * counted as running long after any keyboard animation could last has
     * lost its end, and is written off here rather than trusted.
     */
    fun syncOnReturn() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val animating = running > 0 &&
            SystemClock.uptimeMillis() - lastStartedAt < LONGEST_ANIMATION_MS
        if (animating) return
        running = 0
        root.post(::sync)
    }

    private fun sync() {
        if (running > 0) return
        val view = flutterViewIn(root) ?: return
        val insets = view.rootWindowInsets ?: return
        view.onApplyWindowInsets(insets)
    }

    private fun flutterViewIn(view: View): FlutterView? {
        if (view is FlutterView) return view
        if (view !is ViewGroup) return null
        for (index in 0 until view.childCount) {
            flutterViewIn(view.getChildAt(index))?.let { return it }
        }
        return null
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private inner class KeyboardAnimations :
        WindowInsetsAnimation.Callback(DISPATCH_MODE_CONTINUE_ON_SUBTREE) {

        override fun onPrepare(animation: WindowInsetsAnimation) {
            if (!animation.movesKeyboard) return
            running++
            lastStartedAt = SystemClock.uptimeMillis()
        }

        override fun onProgress(
            insets: WindowInsets,
            runningAnimations: MutableList<WindowInsetsAnimation>,
        ): WindowInsets = insets

        override fun onEnd(animation: WindowInsetsAnimation) {
            if (!animation.movesKeyboard) return
            running = (running - 1).coerceAtLeast(0)
            if (running == 0) root.post(::sync)
        }

        private val WindowInsetsAnimation.movesKeyboard: Boolean
            get() = typeMask and WindowInsets.Type.ime() != 0
    }

    private companion object {
        const val LONGEST_ANIMATION_MS = 1000L
    }
}
