VIVADO ?= vivado
BSR ?= ~/projects/bsr/target/release/bsr

PROJECT = project_1
TOP = design_1_wrapper

all:
	echo "TODO"

vivado: $(PROJECT).xpr
	$(VIVADO) -mode gui $(PROJECT).xpr

project: $(PROJECT).xpr
synth: $(PROJECT).runs/synth_1/$(TOP).dcp
impl: $(PROJECT).runs/impl_1/$(TOP)_routed.dcp
bit: $(PROJECT).bit
bin: $(PROJECT).bin
xsa: $(PROJECT).xsa

lint:
	for dir in rtl tests; do \
		$(MAKE) -C $$dir lint; \
	done

tests:
	$(MAKE) -C tests

$(PROJECT).xpr: create_project.tcl
	$(VIVADO) -mode batch -nojournal -nolog -source $<

$(PROJECT).runs/synth_1/$(TOP).dcp: rtl/*.v | $(PROJECT).xpr
	echo "update_module_reference [get_ips]" > _synth.tcl
	echo "reset_run synth_1" >> _synth.tcl
	echo "launch_runs -jobs 2 synth_1" >> _synth.tcl
	echo "wait_on_run synth_1" >> _synth.tcl
	$(VIVADO) -mode batch -nojournal -nolog -source _synth.tcl $(PROJECT).xpr
	rm _synth.tcl

$(PROJECT).runs/impl_1/$(TOP)_routed.dcp: $(PROJECT).runs/synth_1/$(TOP).dcp
	echo "reset_run impl_1" > _impl.tcl
	echo "launch_runs -jobs 2 impl_1" >> _impl.tcl
	echo "wait_on_run impl_1" >> _impl.tcl
	$(VIVADO) -mode batch -nojournal -nolog -source _impl.tcl $(PROJECT).xpr
	rm _impl.tcl

# This bitstream output name matches the Vivado UI default...
$(PROJECT).runs/impl_1/$(TOP).bit: $(PROJECT).runs/impl_1/$(TOP)_routed.dcp
	echo "open_run impl_1" > _bit.tcl
	echo "write_bitstream -force $(PROJECT).runs/impl_1/$(TOP).bit" >> _bit.tcl
	$(VIVADO) -mode batch -nojournal -nolog -source _bit.tcl $(PROJECT).xpr
	rm _bit.tcl

$(PROJECT).bit: $(PROJECT).runs/impl_1/$(TOP).bit
	ln -f -s $(PROJECT).runs/impl_1/$(TOP).bit $(PROJECT).bit

$(PROJECT).bin: project_1.bit
	$(BSR) -i $< > $@

$(PROJECT).xsa: $(PROJECT).xpr
	# TODO: is there some kind of "generate block diagram" we can do here?
	echo "write_hw_platform -fixed -minimal -force $@" > _xsa.tcl
	$(VIVADO) -mode batch -nojournal -nolog -source _xsa.tcl $(PROJECT).xpr
	rm _xsa.tcl

create_project.tcl:
	echo "write_project_tcl -target_proj_dir . -force $@" > _write_project.tcl
	$(VIVADO) -mode batch -nojournal -nolog -source _write_project.tcl $(PROJECT).xpr
	rm _write_project.tcl

clean:
	rm -rf $(PROJECT).{bit,bin,cache,gen,hw,ip_user_files,runs,sim,srcs,xpr,xsa}
	rm -rf vivado*.{jou,log,str} .Xil
	rm -rf _*.tcl
	$(MAKE) -C tests clean

.PHONY: all vivado project synth impl bit bin xsa lint tests clean
