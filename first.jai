WIN_BUILD_ENABLED :: true;


configure_options :: (options: *Build_Options) {
	options.output_executable_name = "file_browser";
	options.use_visual_studio_message_format = true; // Thanks, 4coder
	options.text_output_flags = 0; // I don't need timings much, and I would rather see more code or more errors in *compilation* window.
}

run_compilation :: (w: Workspace) {
	add_build_file("test.jai", w);
}

#run build();
build :: () {
	format := *context.print_style.default_format_struct;
        format.use_newlines_if_long_form = true;
	
	w := compiler_create_workspace("file browser");
	options := get_build_options();
	configure_options(*options);
	set_build_options(options, w);
	run_compilation(w);
	
	set_build_options_dc(.{do_output=false});
}

#import "File_Utilities";
#import "Basic";
#import "Compiler";