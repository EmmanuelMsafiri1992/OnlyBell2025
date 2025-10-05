// Contains functions for updating real-time dashboard data (metrics, current time).
import { showFlashMessage } from './ui.js';

/**
 * Updates the displayed current time and timezone on the dashboard.
 * Fetches server time to ensure accuracy with alarm triggering.
 */
export async function updateCurrentTime() {
    const currentTimeElement = document.getElementById("currentTime");
    const timezoneElement = document.getElementById("timezone");
    if (currentTimeElement && timezoneElement) {
        try {
            // Fetch server time from the backend
            const response = await fetch('/api/server_time');
            const serverTime = await response.json();

            // Parse the server time and display it
            const serverDate = new Date(serverTime.time);
            currentTimeElement.textContent = serverDate.toLocaleTimeString();
            timezoneElement.textContent = serverTime.timezone;
        } catch (error) {
            // Fallback to browser time if server time fetch fails
            console.warn("Failed to fetch server time, using browser time:", error);
            const now = new Date();
            currentTimeElement.textContent = now.toLocaleTimeString();
            timezoneElement.textContent = Intl.DateTimeFormat().resolvedOptions().timeZone;
        }
    }
}

/**
 * Fetches system metrics (CPU, memory, uptime) from the backend and updates the dashboard UI.
 */
export async function updateMetrics() {
    try {
        const response = await fetch('/api/metrics');
        const metrics = await response.json();

        if (metrics.error) {
            console.error("Error fetching metrics:", metrics.error);
            return;
        }

        const cpu = metrics.process.cpu_percent;
        const memory = metrics.process.memory_mb;
        const systemMemory = metrics.system.memory_percent;
        const uptime = metrics.process.uptime;

        const cpuBar = document.getElementById("cpuBar");
        const cpuText = document.getElementById("cpuText");
        const memoryText = document.getElementById("memoryText");
        const systemMemoryBar = document.getElementById("systemMemoryBar");
        const systemMemoryText = document.getElementById("systemMemoryText");
        const uptimeText = document.getElementById("uptimeText");

        if (cpuBar) cpuBar.style.width = cpu + "%";
        if (cpuText) cpuText.textContent = cpu.toFixed(1) + "%";
        if (memoryText) memoryText.textContent = memory.toFixed(1) + " MB";
        if (systemMemoryText) systemMemoryText.textContent = systemMemory.toFixed(1) + "%";
        if (systemMemoryBar) systemMemoryBar.style.width = systemMemory + "%";
        if (uptimeText) uptimeText.textContent = uptime;

    } catch (error) {
        console.error("Failed to fetch metrics:", error);
    }
}
