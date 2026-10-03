# Keep the upstream package cache untouched. Compile a local copy of its
# Windows renderer with thermal pages fitted to the driver's printable width.
get_target_property(printing_source_dir printing_plugin SOURCE_DIR)
get_target_property(printing_sources printing_plugin SOURCES)
set(print_job_source "${printing_source_dir}/print_job.cpp")
file(READ "${print_job_source}" print_job_code)
set(original_render [=[    FPDF_RenderPage(hDC, page, -marginLeft, -marginTop, bWidth, bHeight, 0,
                    FPDF_ANNOT | FPDF_PRINTING);]=])
set(thermal_render [=[    // Thermal drivers can expose a printable surface narrower than the roll.
    // Fit the whole PDF into that surface, keeping its aspect ratio and never
    // enlarging it. Start at the printable origin instead of the paper origin.
    int renderX = -marginLeft;
    int renderY = -marginTop;
    if (pdfWidth <= 81.0 * pdfDpi / 25.4) {
      const int printableWidth = GetDeviceCaps(hDC, HORZRES);
      if (printableWidth > 0 && bWidth > 0) {
        const double scale = bWidth > printableWidth
            ? static_cast<double>(printableWidth) / bWidth : 1.0;
        bWidth = static_cast<int>(bWidth * scale);
        bHeight = static_cast<int>(bHeight * scale);
        renderX = 0;
        renderY = 0;
      }
    }
    FPDF_RenderPage(hDC, page, renderX, renderY, bWidth, bHeight, 0,
                    FPDF_ANNOT | FPDF_PRINTING);]=])
# Normalize line endings before matching the upstream implementation.
string(REPLACE "\r\n" "\n" print_job_code "${print_job_code}")
string(FIND "${print_job_code}" "${original_render}" render_position)
if(render_position EQUAL -1)
  message(FATAL_ERROR "Printing renderer changed; review the thermal width patch before building.")
endif()
string(REPLACE "${original_render}" "${thermal_render}" print_job_code "${print_job_code}")
set(patched_print_job "${CMAKE_CURRENT_BINARY_DIR}/thermal_print_job.cpp")
file(WRITE "${patched_print_job}" "${print_job_code}")
list(FILTER printing_sources EXCLUDE REGEX "(^|/)print_job\\.cpp$")
set_property(TARGET printing_plugin PROPERTY SOURCES "${printing_sources}")
target_sources(printing_plugin PRIVATE "${patched_print_job}")
target_include_directories(printing_plugin PRIVATE "${printing_source_dir}")
