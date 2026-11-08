module ModelBuilder
  # Instructions for the two stages of an AI Build task (same text for every
  # agent program; the direct-API agent gets the equivalent as tools).
  module Prompts
    def self.kit_help
      <<~MD
        Helpers inside your scripts (meters, world coordinates, Z up; they apply all group transforms for you —
        use them instead of reading raw `bounds`, which are in LOCAL coordinates of nested groups):
        - `ModelBuilder::Kit.mark('p1')` / `('s1')` -> the designer's mark: `{point:}` or `{points:, kind:}`
        - `ModelBuilder::Kit.around([x,y,z], 15)` -> groups/components near a point with world bounds, tags, size
        - `ModelBuilder::Kit.world_bounds('su:123')` -> `{min:, max:}`; `ModelBuilder::Kit.find('su:123')` -> entity
        - `ModelBuilder::Kit.ray([x,y,z], [0,0,-1])` -> first hit `{point:, path:, normal:}`; `Kit.level_at(x, y, z)` -> floor/ceiling
        - `ModelBuilder::Kit.proposal('Roof plant')` -> the group to build into (tag MB_Proposal)
        - `ModelBuilder::Kit.box(group.entities, [x0,y0,z0], [x1,y1,z1], material: 'Grey')`,
          `ModelBuilder::Kit.extrude(group.entities, [[x,y],...], z0, height)`
        - `ModelBuilder::Kit.render(out_dir, 'name', eye: [..], target: [..])` -> PNG (the designer's camera is restored)
      MD
    end

    def self.script_help(t)
      <<~MD
        Run SketchUp Ruby in the designer's OPEN model through the live link: write a .rb file that defines

        ```ruby
        module MBScript
          def self.run(model, out_dir)
            # ... SketchUp Ruby API + ModelBuilder::Kit helpers ...
            "short result text (JSON is fine)"
          end
        end
        ```

        then run: `python "#{Tasks.mb_exec_path}" --task "#{t.dir}" <your_script.rb>` (prints JSON `{ok, result | error, backtrace, files, created}`).

        #{kit_help}
      MD
    end

    def self.plan(t, exp)
      no_vision = exp[:packet][:references]&.any? { |r| r[:file].to_s =~ /\.(png|jpe?g|bmp|gif|webp|tiff?)\z/i }
      <<~MD
        # AI Build task #{t.id} — STAGE 1: PLAN (do not build yet)

        You are the operational agent for **Model Builder**, a SketchUp plugin. A designer marked a place in their model and
        asked for something to be built there. The model is OPEN in SketchUp right now.

        1. Read the brief: `#{exp[:brief_path]}`. It has the task, the marks (with the geometry AROUND each mark),
           the references and the warnings. #{no_vision ? 'View the reference images (use the downscaled previews).' : ''}
           #{exp[:packet][:project_notes] ? "Project notes (read first): `#{exp[:packet][:project_notes]}`" : ''}
        2. Inspect the model only as much as you need. In this stage every script you run is **rolled back**
           (read-only), so you can query freely. Keep it short: a few targeted queries, not a survey of the whole model.
        3. Write the plan to `#{t.plan_path}` (Markdown, short):
           - **Task** as you understand it, in one or two sentences.
           - **Where:** the exact location (coordinates, level, the element it sits on or replaces).
           - **What you will build:** elements, sizes, materials; which reference you follow for what.
           - **Assumptions** and **questions** (only what really matters).
        4. Then STOP. The designer reviews the plan and approves it; you will then be asked to build.

        #{script_help(t)}
      MD
    end

    def self.build(t, comment)
      <<~MD
        # AI Build task #{t.id} — STAGE 2: BUILD

        The designer **approved your plan** (`#{t.plan_path}`).#{comment.to_s.strip.empty? ? '' : " Their comment: #{comment}"}
        Build it now in the open model. Brief: `#{t.brief_path}`.

        - Scripts now take effect (each script = one undo step; an error rolls that script back).
        - Put ALL new geometry in ONE group made with `ModelBuilder::Kit.proposal('<short title>')`. Do not change existing
          geometry unless the plan says so. The designer can Reject everything you created.
        - Work in a few solid steps; check the result (bounds, a render) once at the end.
        - The designer is not watching each step and will not answer questions now: make sensible choices and list them.
        - Finally write a short report to `#{t.reply_path}`: what you built (where, sizes), deviations from the plan,
          open questions. Then stop.

        #{script_help(t)}
      MD
    end

    def self.revise(t, comment, resumed:)
      head = resumed ? "The designer wants changes to your plan:\n\n> #{comment}\n" : File.read(t.prompt_path, encoding: 'UTF-8') +
                                                                                      "\n\n## The designer's comments on your previous plan\n\n> #{comment}\n"
      <<~MD
        #{head}
        Update the plan accordingly and write it again to `#{t.plan_path}`. Still STAGE 1: do not build. Then STOP.
      MD
    end
  end
end
