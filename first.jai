WIN_BUILD_ENABLED :: true;

configure_options :: (options: *Build_Options) {
}

sync_compile_c :: (path: string, output: string) -> bool {
	res := run_command("cc", "-Wall", "-Wextra", "-pedantic", "-c", "-o", output, path);
	if res.exit_code != 0 {
		log("Error on compiling C file\n");
		return false;
	}
	return true;
}

compile_imgui_test :: () {
	w := compiler_create_workspace("imgui test");
	options := get_build_options();
	options.output_executable_name = "imgui";
	options.use_visual_studio_message_format = true;
	options.text_output_flags = 0;
	set_build_options(options, w);
	add_build_file("imgui_test.jai", w);
}

#run build();
build :: () {
	format := *context.print_style.default_format_struct;
        format.use_newlines_if_long_form = true;
	compile_imgui_test();
	set_build_options_dc(.{do_output=false});
}

#import "Process";
#import "File_Utilities";
#import "Basic";
using Compiler :: #import "Compiler";
