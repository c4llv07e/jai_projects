WIN_BUILD_ENABLED :: true;

configure_options :: (options: *Build_Options) {
	options.output_executable_name = "linker";
	options.use_visual_studio_message_format = true; // Thanks, 4coder
	options.text_output_flags = 0; // I don't need timings much, and I would rather see more code or more errors in *compilation* window.
}

run_compilation :: (w: Workspace) {
	add_build_file("linker.jai", w);
}

sync_compile_c :: (path: string, output: string) -> bool {
	res := run_command("cc", "-Wall", "-Wextra", "-pedantic", "-c", "-o", output, path);
	if res.exit_code != 0 {
		log("Error on compiling C file\n");
		return false;
	}
	return true;
}

#run build();
build :: () {
	format := *context.print_style.default_format_struct;
        format.use_newlines_if_long_form = true;
	sync_compile_c("test.c", "test.o");
	w := compiler_create_workspace("file browser");
	options := get_build_options();
	set_build_options_dc(.{do_output=false});
	configure_options(*options);
	set_build_options(options, w);
	// compiler_begin_intercept(w);
	run_compilation(w);
#if false {
		while true {
			message := compiler_wait_for_message();
			if message.kind == .COMPLETE break;
			if message.kind == .PHASE {
				phase_message := cast(*Message_Phase)message;
				phase := phase_message.phase;
				if phase == .READY_FOR_CUSTOM_LINK_COMMAND {
					run_custom_link_command(message.workspace, phase_message);
				}
			}
		}
	}
}

run_custom_link_command :: (w: Workspace, message: *Message) {
}

#import "Process";
#import "File_Utilities";
#import "Basic";
using Compiler :: #import "Compiler";